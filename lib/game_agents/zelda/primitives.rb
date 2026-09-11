# frozen_string_literal: true
# Reusable action primitives for the Zelda game-playing agent (see docs/ZELDA_AGENT.md).
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
require_relative '../../../profiling/utils'

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

# Link's own sprite consistently uses tile IDs 0 (left half) / 2 (right half) in every settled
# (post-move-tiles-settle) OAM dump taken this session, across multiple rooms and screens,
# regardless of position -- unlike the position-exclusion approach, this doesn't get confused by
# new unknown sprites (objects, NPCs, wildlife) appearing as the overworld gets explored. Prefer
# this; fall back to exclusion-based matching (stationary_positions) only if no tile:0 entry is
# present (e.g. an animation frame this hasn't been observed to need, in a settled read).
LINK_LEFT_TILE = 0

def find_link_by_tile(mmu)
  sprite = oam_sprites(mmu).find { |s| s[:tile] == LINK_LEFT_TILE }
  sprite && { y: sprite[:y], x: sprite[:x] }
end

# stationary_positions: array of [y, x] for known-fixed NPCs/decorations to exclude.
# Returns the (y, x) of whichever active sprite pair is left, or nil if none/ambiguous.
# OAM can land on a transient frame (mid-animation, sprite momentarily not drawn) -- retry a
# few times with a short settle instead of trusting a single sample.
def find_link(cpu, ppu, apu, mmu, stationary_positions:, retries: 5)
  retries.times do |i|
    by_tile = find_link_by_tile(mmu)
    return by_tile if by_tile

    active = oam_sprites(mmu).reject { |s| stationary_positions.include?([s[:y], s[:x]]) }
    return { y: active.first[:y], x: active.first[:x] } unless active.empty?

    run_steps(cpu, ppu, apu, 20_000) if i < retries - 1
  end
  nil
end

# Same as find_link but for a single settled read with a known previous position on hand (used
# right after a move_tiles step) -- prefers tile-ID matching, falls back to nearest-neighbor
# exclusion if no tile:0 entry is present.
def nearest_link_pos(mmu, stationary_positions, last_pos, max_jump: 20)
  by_tile = find_link_by_tile(mmu)
  return by_tile if by_tile

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
