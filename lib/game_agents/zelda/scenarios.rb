# frozen_string_literal: true

# Named checkpoints along the explored path, so scripts don't replay the ~150s boot+intro (or the
# minutes of scripted movement beyond it) every run. Each checkpoint function loads its saved
# state if present, otherwise builds it from the previous checkpoint (or from boot) and saves it
# via Zelda::Checkpoint -- see that file for why a plain Marshal.dump works on the emulator state.
require 'fileutils'
require_relative 'navigator'
require_relative 'checkpoint'

module Zelda
  module Scenarios
    CHECKPOINT_DIR = '/tmp/zelda_checkpoints'
    STATIONARY_STARTING_HOUSE = [[80, 120], [80, 128], [56, 80], [56, 88]].freeze

    def self.checkpoint_path(name) = File.join(CHECKPOINT_DIR, "#{name}.marshal")

    def self.cached(name, rom:)
      path = checkpoint_path(name)
      return Checkpoint.load(path) if File.exist?(path)

      cpu, ppu, apu, mmu, keys = yield
      FileUtils.mkdir_p(CHECKPOINT_DIR)
      Checkpoint.save(path, cpu:, ppu:, apu:, mmu:, keys:)
      [cpu, ppu, apu, mmu, keys]
    end

    # Boots the save, plays through the intro dialogues and gets the shield from Tarkin -- still
    # inside the starting house. See ZELDA_BACKLOG.md "Exited the house".
    def self.after_shield_interior(rom: 'roms/zelda_la_dx.gbc')
      cached('after_shield_interior', rom:) do
        cpu, ppu, apu, mmu, keys = build_emulator(rom, with_input: true)

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
        [cpu, ppu, apu, mmu, keys]
      end
    end

    # Continues from after_shield_interior and exits the starting house's south door into the
    # front yard. See ZELDA_BACKLOG.md "Exited the house".
    def self.front_yard(rom: 'roms/zelda_la_dx.gbc')
      cached('front_yard', rom:) do
        cpu, ppu, apu, mmu, keys = after_shield_interior(rom:)

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

          dir = if dy.abs >= dx.abs
                  dy.positive? ? :down : :up
                else
                  (dx.positive? ? :right : :left)
                end
          moved = move_tiles(cpu, ppu, apu, keys, mmu, dir, 1, stationary_positions: STATIONARY_STARTING_HOUSE)
          next if moved.positive?

          alt_dir = if dy.abs >= dx.abs
                      dx.positive? ? :right : :left
                    else
                      (dy.positive? ? :down : :up)
                    end
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

          dir = if dy.abs >= dx.abs
                  dy.positive? ? :down : :up
                else
                  (dx.positive? ? :right : :left)
                end
          moved = move_tiles(cpu, ppu, apu, keys, mmu, dir, 1, stationary_positions: STATIONARY_STARTING_HOUSE)
          next if moved.positive?

          alt_dir = if dy.abs >= dx.abs
                      dx.positive? ? :right : :left
                    else
                      (dy.positive? ? :down : :up)
                    end
          move_tiles(cpu, ppu, apu, keys, mmu, alt_dir, 1, stationary_positions: STATIONARY_STARTING_HOUSE)
        end
        8.times { move_tiles(cpu, ppu, apu, keys, mmu, :down, 1, stationary_positions: STATIONARY_STARTING_HOUSE) }
        [cpu, ppu, apu, mmu, keys]
      end
    end

    # Continues from front_yard to the 3rd overworld screen (a house + wandering villager, two
    # screen-scrolls south/west of the front yard). See ZELDA_BACKLOG.md "Overworld exploration".
    def self.villager_screen(rom: 'roms/zelda_la_dx.gbc')
      cached('villager_screen', rom:) do
        cpu, ppu, apu, mmu, keys = front_yard(rom:)
        no_exclusions = []
        move_tiles(cpu, ppu, apu, keys, mmu, :left, 1, stationary_positions: no_exclusions)
        25.times { move_tiles(cpu, ppu, apu, keys, mmu, :down, 1, stationary_positions: no_exclusions) }
        40.times { move_tiles(cpu, ppu, apu, keys, mmu, :down, 1, stationary_positions: no_exclusions) }
        30.times { move_tiles(cpu, ppu, apu, keys, mmu, :left, 1, stationary_positions: no_exclusions) }
        14.times { move_tiles(cpu, ppu, apu, keys, mmu, :left, 1, stationary_positions: no_exclusions) }
        # The last move can leave a scroll animation still in flight (position keeps drifting with
        # zero input for ~200k cycles past move_tiles' own SETTLE_FRAMES) -- checkpointing mid-scroll
        # froze that drift into the saved state, so every direction probed afterward inherited the
        # same pending camera pan regardless of what was pressed. Run it out before saving.
        run_steps(cpu, ppu, apu, 400_000)
        [cpu, ppu, apu, mmu, keys]
      end
    end
  end
end
