# frozen_string_literal: true
# Reusable action primitives for the Zelda-agent spike (see docs/ZELDA_AGENT.md).
#
# Link has no fixed OAM slot -- the game reassigns which of the 40 sprite slots renders him
# between frames. find_link works around this by exclusion: read all active (on-screen) OAM
# sprites, drop any whose (Y, X) matches a known-stationary NPC, and treat what remains as Link.
# Good enough for a single room with no wandering third sprite; would need a real WRAM address
# for rooms with moving enemies/NPCs alongside Link.
require_relative '/home/user/gemboy/profiling/utils'

TILE_SIZE = 16 # native px per walkable tile

def oam_sprites(mmu)
  (0...40).filter_map do |i|
    base = 0xFE00 + (i * 4)
    y = mmu.read(base)
    next unless y.positive? && y < 160

    { idx: i, y: y, x: mmu.read(base + 1), tile: mmu.read(base + 2), flags: mmu.read(base + 3) }
  end
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

def tap_key(cpu, ppu, apu, keys, key, hold: 60_000, release: 40_000)
  keys.press(key)
  run_steps(cpu, ppu, apu, hold)
  keys.clear
  run_steps(cpu, ppu, apu, release)
end

# Moves up to n tiles in one direction, one tile at a time, verifying real displacement via OAM
# after each step and stopping early on a collision (position didn't move as expected) rather
# than blindly holding input and hoping. Returns the number of tiles actually moved.
#
# Known limitation (found chasing the starting-house door, see ZELDA_BACKLOG.md): this only
# checks the delta's *sign* matches the requested direction, not its magnitude -- a single "moved
# 1" call has been measured landing anywhere from 7px to 31px away (a tile is ~16px), so it can
# silently overshoot or undershoot by close to a full tile. Fine for coarse multi-tile travel, not
# reliable for the final 1-2 tiles of approach to a specific adjacent target -- confirm with an
# OAM read or screenshot before interacting. Also has no multi-segment path planning: chaining
# move_tiles(right, n) then move_tiles(down, m) in a cluttered room can funnel back to the same
# bottleneck tile both times instead of reaching a waypoint. Check an intermediate
# screenshot/position before trusting a chained multi-segment route.
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
    tap_key(cpu, ppu, apu, keys, direction, hold: 350_000, release: 60_000)
    after = find_link(cpu, ppu, apu, mmu, stationary_positions: stationary_positions)
    break if before.nil? || after.nil?

    delta = after[axis] - before[axis]
    break if delta.zero? || (delta <=> 0) != sign # stopped early: wall/object/no movement

    moved += 1
  end
  moved
end

# Assumes Link is already adjacent to and facing the target (talk / lift-pot both use A).
def interact(cpu, ppu, apu, keys)
  tap_key(cpu, ppu, apu, keys, :a, hold: 30_000, release: 1_500_000)
end
