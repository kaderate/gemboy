# frozen_string_literal: true

require_relative 'primitives'
require_relative 'tilemap_reader'
require_relative 'tile_catalog'

# Tests ONE gameplay cell of movement at a time and feeds the result into a shared TileCatalog,
# so a tile is only ever probed once across the whole game -- unlike RoomMap::Recorder's per-
# screen empirical rediscovery (kept as a validation tool, see ZELDA_BACKLOG.md), the point here
# is that classifying the same visual tile (grass, wall...) on screen N+1 costs zero further
# probing once it was classified on screen N.
module Zelda
  module TileClassifier
    CELL_PX = 16 # matches move_tiles' step size (TILE_SIZE in primitives.rb) -- one gameplay
    # cell is 2x2 BG tiles (8px each), not a single BG tile.
    SCROLL_JUMP_THRESHOLD = 40 # px; same screen-exit heuristic RoomMap uses (see room_map.rb)
    DELTA = { up: [-1, 0], down: [1, 0], left: [0, -1], right: [0, 1] }.freeze
    OPPOSITE = { up: :down, down: :up, left: :right, right: :left }.freeze

    # Link's OAM position is his top-left tracked half (LINK_LEFT_TILE, see primitives.rb); the
    # hardware sprite offset is screen_y = oam_y - 16, screen_x = oam_x - 8 (lib/ppu/sprite_scanner.rb).
    # Feet (bottom of his 16px-tall sprite) and horizontal center (he's the left half of a 16px-wide
    # sprite) anchor which 16x16 gameplay cell he occupies -- calibrated against a screenshot: the
    # computed cell landed exactly on the door tile in overworld_front_yard, matching the door's
    # visible position (see ZELDA_BACKLOG.md).
    def self.cell_for(pos)
      feet_y = pos[:y] - 1 # (y - 16) + 15
      center_x = pos[:x] # (x - 8) + 8
      [feet_y / CELL_PX, center_x / CELL_PX]
    end

    # The 4 BG tiles (2x2, 8px each) making up gameplay cell (cell_row, cell_col), from a grid
    # already read via TilemapReader.visible_grid.
    def self.tiles_in_cell(grid, cell_row, cell_col)
      rows = [cell_row * 2, (cell_row * 2) + 1]
      cols = [cell_col * 2, (cell_col * 2) + 1]
      grid.select { |t| rows.include?(t.screen_row) && cols.include?(t.screen_col) }
    end

    # Attempts one gameplay cell of movement in `direction`, retrying a not-yet-moved result (the
    # "creeping collision" pattern -- see ZELDA_BACKLOG.md's movement model) up to `retries` times.
    # Outcome is decided by exact cell equality (no distance threshold needed -- positions are
    # quantized to cells now) except for a screen-exit, still a large-pixel-jump heuristic.
    # Returns [outcome, before_cell, after_cell_or_nil], outcome in :ok/:blocked/:scroll/:lost.
    def self.probe(cpu, ppu, apu, keys, mmu, direction, stationary_positions:, retries: 8)
      before_pos = find_link(cpu, ppu, apu, mmu, stationary_positions:)
      return [:lost, nil, nil] if before_pos.nil?

      before_cell = cell_for(before_pos)
      dy, dx = DELTA[direction]
      expected = [before_cell[0] + dy, before_cell[1] + dx]

      retries.times do |i|
        move_tiles(cpu, ppu, apu, keys, mmu, direction, 1, stationary_positions:)
        after_pos = find_link(cpu, ppu, apu, mmu, stationary_positions:)
        last_attempt = i == retries - 1
        if after_pos.nil?
          return [:lost, before_cell, nil] if last_attempt

          next # find_link already retries internally -- a nil here is a rarer, still-transient miss
        end

        delta_px = Math.sqrt(((after_pos[:y] - before_pos[:y])**2) + ((after_pos[:x] - before_pos[:x])**2))
        return [:scroll, before_cell, nil] if delta_px >= SCROLL_JUMP_THRESHOLD

        after_cell = cell_for(after_pos)
        return [:ok, before_cell, after_cell] if after_cell == expected
        return [:blocked, before_cell, before_cell] if last_attempt
      end
    end

    # Runs `probe`, then on :ok records the arrival cell's 4 tiles as passable from the opposite
    # direction (Link entered them by moving `direction`, i.e. they let him in from `OPPOSITE`).
    # :blocked records nothing -- an attempt refused from one approach doesn't prove a permanent
    # wall (this engine's collision has shown order/approach-dependent quirks, see
    # ZELDA_BACKLOG.md's movement model), so absence of evidence isn't written as evidence of a
    # wall; ScreenMap decides what to do with a still-untested direction for its own pathing.
    # Reads the tile grid AFTER the move completes, not before -- some screens pan their camera
    # continuously even for in-room moves (see overworld_screen3's finding), so a pre-move grid
    # can already be stale by the time the target cell needs to be looked up.
    def self.probe_and_classify!(cpu, ppu, apu, keys, mmu, direction, catalog:, screen_name:, stationary_positions:,
                                 retries: 8)
      outcome, _before_cell, after_cell = probe(cpu, ppu, apu, keys, mmu, direction, stationary_positions:, retries:)
      return outcome unless outcome == :ok

      grid = Zelda::TilemapReader.visible_grid(ppu, mmu)
      tiles_in_cell(grid, *after_cell).each do |t|
        catalog.record_passable!(t.pattern_hash, OPPOSITE[direction], source: 'empirique',
                                                                      first_seen: { screen: screen_name,
                                                                                    row: t.screen_row,
                                                                                    col: t.screen_col })
      end
      outcome
    end
  end
end
