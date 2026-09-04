# frozen_string_literal: true
# Reusable checkpoint: boots the save, plays through the intro dialogues, gets the shield from
# Tarkin, and exits the starting house's south door into the front yard. Used as the starting
# point for scripts exploring beyond the house, so the (now well-validated) opening sequence
# doesn't need to be re-derived each time. See ZELDA_BACKLOG.md's "Exited the house" section.
require_relative 'zelda_navigator'

STATIONARY_STARTING_HOUSE = [[80, 120], [80, 128], [56, 80], [56, 88]].freeze

def reach_front_yard(cpu, ppu, apu, keys, mmu)
  run_steps(cpu, ppu, apu, 60_000_000)
  tap_key(cpu, ppu, apu, keys, :start, hold: 100_000)
  run_steps(cpu, ppu, apu, 15_000_000)
  tap_key(cpu, ppu, apu, keys, :start, hold: 100_000)
  run_steps(cpu, ppu, apu, 5_000_000)
  tap_key(cpu, ppu, apu, keys, :a, hold: 30_000, release: 500_000)
  tap_key(cpu, ppu, apu, keys, :start, hold: 100_000, release: 3_000_000)
  tap_key(cpu, ppu, apu, keys, :start, hold: 100_000, release: 3_000_000)
  run_steps(cpu, ppu, apu, 15_000_000)
  6.times { interact(cpu, ppu, apu, keys) }

  move_tiles(cpu, ppu, apu, keys, mmu, :down, 2, stationary_positions: STATIONARY_STARTING_HOUSE)
  move_tiles(cpu, ppu, apu, keys, mmu, :right, 3, stationary_positions: STATIONARY_STARTING_HOUSE)
  move_tiles(cpu, ppu, apu, keys, mmu, :up, 1, stationary_positions: STATIONARY_STARTING_HOUSE)

  target = { y: 80, x: 112 }
  40.times do
    pos = find_link(cpu, ppu, apu, mmu, stationary_positions: STATIONARY_STARTING_HOUSE)
    break if pos.nil?

    dy = target[:y] - pos[:y]
    dx = target[:x] - pos[:x]
    break if dy.abs <= 10 && dx.abs <= 10

    dir = dy.abs >= dx.abs ? (dy.positive? ? :down : :up) : (dx.positive? ? :right : :left)
    moved = move_tiles(cpu, ppu, apu, keys, mmu, dir, 1, stationary_positions: STATIONARY_STARTING_HOUSE)
    next if moved.positive?

    alt_dir = dy.abs >= dx.abs ? (dx.positive? ? :right : :left) : (dy.positive? ? :down : :up)
    move_tiles(cpu, ppu, apu, keys, mmu, alt_dir, 1, stationary_positions: STATIONARY_STARTING_HOUSE)
  end
  30.times do
    pos = find_link(cpu, ppu, apu, mmu, stationary_positions: STATIONARY_STARTING_HOUSE)
    break if pos.nil? || target[:x] - pos[:x] <= 2

    moved = move_tiles(cpu, ppu, apu, keys, mmu, :right, 1, stationary_positions: STATIONARY_STARTING_HOUSE)
    break if moved.zero?
  end
  tap_key(cpu, ppu, apu, keys, :right, hold: 30_000, release: 500_000)
  12.times { interact(cpu, ppu, apu, keys) } # exhausts the shield-gift conversation

  door_target = { y: 148, x: 72 }
  50.times do
    pos = find_link(cpu, ppu, apu, mmu, stationary_positions: STATIONARY_STARTING_HOUSE)
    break if pos.nil?

    dy = door_target[:y] - pos[:y]
    dx = door_target[:x] - pos[:x]
    break if dy.abs <= 8 && dx.abs <= 16

    dir = dy.abs >= dx.abs ? (dy.positive? ? :down : :up) : (dx.positive? ? :right : :left)
    moved = move_tiles(cpu, ppu, apu, keys, mmu, dir, 1, stationary_positions: STATIONARY_STARTING_HOUSE)
    next if moved.positive?

    alt_dir = dy.abs >= dx.abs ? (dx.positive? ? :right : :left) : (dy.positive? ? :down : :up)
    move_tiles(cpu, ppu, apu, keys, mmu, alt_dir, 1, stationary_positions: STATIONARY_STARTING_HOUSE)
  end
  8.times { move_tiles(cpu, ppu, apu, keys, mmu, :down, 1, stationary_positions: STATIONARY_STARTING_HOUSE) }
end

# Continues from reach_front_yard to the 3rd overworld screen (a house + wandering villager, two
# screen-scrolls south/west of the front yard). See ZELDA_BACKLOG.md's "Overworld exploration".
def reach_villager_screen(cpu, ppu, apu, keys, mmu)
  reach_front_yard(cpu, ppu, apu, keys, mmu)
  no_exclusions = []
  move_tiles(cpu, ppu, apu, keys, mmu, :left, 1, stationary_positions: no_exclusions)
  25.times { move_tiles(cpu, ppu, apu, keys, mmu, :down, 1, stationary_positions: no_exclusions) }
  40.times { move_tiles(cpu, ppu, apu, keys, mmu, :down, 1, stationary_positions: no_exclusions) }
  30.times { move_tiles(cpu, ppu, apu, keys, mmu, :left, 1, stationary_positions: no_exclusions) }
  14.times { move_tiles(cpu, ppu, apu, keys, mmu, :left, 1, stationary_positions: no_exclusions) }
end
