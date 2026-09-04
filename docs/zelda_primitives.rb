# frozen_string_literal: true
# Reusable action primitives for the Zelda-agent spike (see docs/ZELDA_AGENT.md).
#
# Link has no fixed OAM slot -- the game reassigns which of the 40 sprite slots renders him
# between frames. find_link works around this by exclusion: read all active (on-screen) OAM
# sprites, drop any whose (Y, X) matches a known-stationary NPC, and treat what remains as Link.
# Good enough for a single room with no wandering third sprite; would need a real WRAM address
# for rooms with moving enemies/NPCs alongside Link.
#
# Movement is tile-locked: a directional press held for >=1 frame commits to one fixed,
# deterministic trajectory that plays out over ~22-28 frames regardless of how much longer the
# key stays held (measured via a fork-per-trial hold-duration sweep, holds of 1/2/4/8/16 frames
# all produced byte-identical trajectories). Two outcomes only: it resolves to +/-~14px along the
# pressed axis (a completed step -- not exactly TILE_SIZE, empirically ~14px), or it bounces back
# to within a few px of the starting position (blocked by a collision). Reading position before
# that settle window closes is what produced the earlier 7-31px noise (see ZELDA_BACKLOG.md) --
# it was catching different mid-animation frames, not measuring real per-tap variance.
require_relative '/home/user/gemboy/profiling/utils'

TILE_SIZE = 16 # native px per walkable tile grid cell (measured step is ~14px, see move_tiles)
FRAME_CYCLES = 70224 # T-cycles/frame, fixed regardless of instruction mix
TRIGGER_FRAMES = 2 # safely above the ~1-frame minimum for the joypad poll to register
SETTLE_FRAMES = 28 # observed full resolution (move or collision-bounce) completes by ~24-26 frames

def oam_sprites(mmu)
  (0...40).filter_map do |i|
    base = 0xFE00 + (i * 4)
    y = mmu.read(base)
    next unless y.positive? && y < 160

    { idx: i, y: y, x: mmu.read(base + 1), tile: mmu.read(base + 2), flags: mmu.read(base + 3) }
  end
end

# run_steps takes an *instruction count*, not raw cycles, but returns actual T-cycles elapsed --
# step in small instruction chunks, accumulating real cycles, for frame-accurate timing.
def run_cycles(cpu, ppu, apu, target_cycles)
  total = 0
  total += run_steps(cpu, ppu, apu, 20) while total < target_cycles
  total
end

# stationary_positions: array of [y, x] for known-fixed NPCs/decorations to exclude.
# Returns the (y, x) of whichever active sprite pair is left, or nil if none/ambiguous.
# OAM can land on a transient frame (mid-animation, sprite momentarily not drawn) -- retry a
# few times with a short settle instead of trusting a single sample.
def find_link(cpu, ppu, apu, mmu, stationary_positions:, retries: 5)
  retries.times do |i|
    active = oam_sprites(mmu).reject { |s| stationary_positions.include?([s[:y], s[:x]]) }
    return { y: active.first[:y], x: active.first[:x] } unless active.empty?

    run_steps(cpu, ppu, apu, 20_000) if i < retries - 1
  end
  nil
end

# Same exclusion logic as find_link, but picks the active candidate nearest to a known previous
# position instead of just "first" -- OAM slot reassignment can otherwise latch onto a stray
# non-Link sprite. Use when a recent trusted position is already in hand (e.g. after find_link).
def nearest_link_pos(mmu, stationary_positions, last_pos, max_jump: 20)
  active = oam_sprites(mmu).reject { |s| stationary_positions.include?([s[:y], s[:x]]) }
  candidate = active.min_by { |s| (s[:y] - last_pos[:y]).abs + (s[:x] - last_pos[:x]).abs }
  return nil if candidate.nil?
  return nil if (candidate[:y] - last_pos[:y]).abs > max_jump || (candidate[:x] - last_pos[:x]).abs > max_jump

  { y: candidate[:y], x: candidate[:x] }
end

def tap_key(cpu, ppu, apu, keys, key, hold: 60_000, release: 40_000)
  keys.press(key)
  run_steps(cpu, ppu, apu, hold)
  keys.clear
  run_steps(cpu, ppu, apu, release)
end

# Moves up to n tiles in one direction, one tile at a time, verifying real displacement via OAM
# after each step and stopping early on a collision rather than blindly holding input and hoping.
# Returns the number of tiles actually moved.
#
# Exploits the tile-locked movement model (see file header): trigger with a short press, wait the
# full settle window, then read the outcome once it's unambiguous -- either a completed step or a
# collision-bounce back near the start. No more guessing at hold duration or reading mid-animation.
def move_tiles(cpu, ppu, apu, keys, mmu, direction, n, stationary_positions:)
  axis, sign = case direction
               when :up then [:y, -1]
               when :down then [:y, 1]
               when :left then [:x, -1]
               when :right then [:x, 1]
               else raise ArgumentError, "unknown direction #{direction}"
               end

  moved = 0
  n.times do
    before = find_link(cpu, ppu, apu, mmu, stationary_positions: stationary_positions)
    break if before.nil?

    keys.press(direction)
    run_cycles(cpu, ppu, apu, TRIGGER_FRAMES * FRAME_CYCLES)
    keys.clear
    run_cycles(cpu, ppu, apu, SETTLE_FRAMES * FRAME_CYCLES)

    after = nearest_link_pos(mmu, stationary_positions, before)
    break if after.nil?

    delta = after[axis] - before[axis]
    break if delta.abs < TILE_SIZE / 2 # collision-bounce settled back near start
    break if (delta <=> 0) != sign # sanity check, shouldn't happen given the model above

    moved += 1
  end
  moved
end

# Assumes Link is already adjacent to and facing the target (talk / lift-pot both use A).
def interact(cpu, ppu, apu, keys)
  tap_key(cpu, ppu, apu, keys, :a, hold: 30_000, release: 1_500_000)
end
