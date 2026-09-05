# frozen_string_literal: true

require_relative 'tilemap_reader'
require_relative 'tile_classifier'
require_relative 'tile_catalog'
require_relative 'screen_grid'

# Builds one screen's directional collision grid (see ScreenGrid), keyed by exact gameplay-cell
# coordinates (see TileClassifier) instead of RoomMap::Recorder's fuzzy pixel-snapped nodes --
# cells are integers, so there's no SNAP_RADIUS ambiguity to get wrong. The actual point of this
# file: a direction is only ever physically tested if the target cell's tiles aren't already
# resolvable from the shared TileCatalog (a wall stays a wall, grass stays grass) -- so the same
# screen explored a second time (or a screen sharing tiles with an already-explored one) costs
# less live testing, trending toward zero as the catalog grows. RoomMap::Recorder remains the
# cross-check: it explores blind, this explores by reading the tiles first, and the two graphs
# should agree (see ZELDA_BACKLOG.md).
module Zelda
  module ScreenMap
    DIRECTIONS = %i[up down left right].freeze
    OPPOSITE = TileClassifier::OPPOSITE
    MAX_RECOVERIES_PER_CELL = 3

    # See ZELDA_BACKLOG.md's RoomMap writeup for why `reset:` (a proc returning a fresh
    # [cpu, ppu, apu, mmu, keys], e.g. reloading a checkpoint) matters: some edges lead to a
    # transition that never resolves within find_link's retry budget. Without `reset` (default),
    # :lost aborts the whole build, matching RoomMap::Recorder's own default behavior.
    def self.build(cpu, ppu, apu, keys, mmu, screen_name:, catalog:, stationary_positions:, max_cells: 40,
                   retries: 8, reset: nil)
      grid = ScreenGrid.new(screen_name)
      start_pos = find_link(cpu, ppu, apu, mmu, stationary_positions:)
      return [grid, :lost] if start_pos.nil?

      frontier = [TileClassifier.cell_for(start_pos)]
      probed = {}
      recovery_attempts = Hash.new(0)

      until frontier.empty?
        return [grid, :max_cells] if probed.size >= max_cells

        cell = frontier.shift
        next if probed[cell]

        state = [cpu, ppu, apu, mmu, keys]
        result = visit_cell!(state, grid, cell, frontier, probed, catalog:, screen_name:, stationary_positions:,
                                                                  retries:, reset:, recovery_attempts:)
        return [grid, :lost] if result == :lost

        cpu, ppu, apu, mmu, keys = result
      end
      [grid, :exhausted]
    end

    def self.visit_cell!(state, grid, cell, frontier, probed, catalog:, screen_name:, stationary_positions:, retries:,
                         reset:, recovery_attempts:)
      cpu, ppu, apu, mmu, keys = state
      path = navigate_to(cpu, ppu, apu, keys, mmu, grid, cell, stationary_positions:)
      if path == :lost
        return :lost unless recoverable?(reset, cell, recovery_attempts)

        cpu, ppu, apu, mmu, keys = reset.call
        frontier << cell
        return [cpu, ppu, apu, mmu, keys]
      end

      probed[cell] = true
      path.each { |dir| move_tiles(cpu, ppu, apu, keys, mmu, dir, 1, stationary_positions:) }

      DIRECTIONS.each do |dir|
        next if grid.edges_for(cell)[dir]

        outcome = resolve_direction!(cpu, ppu, apu, keys, mmu, cell, dir, catalog:, screen_name:,
                                                                          stationary_positions:, retries:)
        if outcome == :lost
          return :lost unless recoverable?(reset, cell, recovery_attempts)

          cpu, ppu, apu, mmu, keys = reset.call
          probed.delete(cell)
          frontier << cell
          break
        end

        apply_outcome!(cpu, ppu, apu, keys, mmu, grid, cell, dir, outcome, frontier, probed, stationary_positions:)
      end
      [cpu, ppu, apu, mmu, keys]
    end

    def self.apply_outcome!(cpu, ppu, apu, keys, mmu, grid, cell, dir, outcome, frontier, probed, stationary_positions:)
      case outcome
      when :scroll
        grid.edges_for(cell)[dir] = :exit
        move_tiles(cpu, ppu, apu, keys, mmu, OPPOSITE[dir], 1, stationary_positions:) # best-effort return
      when :blocked
        grid.edges_for(cell)[dir] = :blocked
      when :ok
        grid.edges_for(cell)[dir] = :ok
        new_cell = grid.cell_after(cell, dir)
        frontier << new_cell unless probed[new_cell]
        return_to_cell_if_moved(cpu, ppu, apu, keys, mmu, cell, dir, stationary_positions:)
      end
    end

    # A skip-derived :ok never physically moved Link; a live-tested :ok did -- rather than track
    # that, just check where he actually is and reverse only if needed.
    def self.return_to_cell_if_moved(cpu, ppu, apu, keys, mmu, cell, dir, stationary_positions:)
      pos = find_link(cpu, ppu, apu, mmu, stationary_positions:)
      return if pos.nil? || TileClassifier.cell_for(pos) == cell

      move_tiles(cpu, ppu, apu, keys, mmu, OPPOSITE[dir], 1, stationary_positions:)
    end

    def self.navigate_to(cpu, ppu, apu, _keys, mmu, grid, target_cell, stationary_positions:)
      pos = find_link(cpu, ppu, apu, mmu, stationary_positions:)
      return :lost if pos.nil?

      current_cell = TileClassifier.cell_for(pos)
      return [] if current_cell == target_cell

      grid.path_to(current_cell, target_cell) || :lost
    end

    # Tries to resolve `dir` from `cell` purely by catalog lookup (no movement) before falling
    # back to a live TileClassifier probe. Returns :ok/:blocked/:scroll/:lost.
    def self.resolve_direction!(cpu, ppu, apu, keys, mmu, cell, dir, catalog:, screen_name:, stationary_positions:,
                                retries:)
      target_cell = ScreenGrid.cell_after(cell, dir)
      grid_tiles = Zelda::TilemapReader.visible_grid(ppu, mmu)
      target_tiles = TileClassifier.tiles_in_cell(grid_tiles, *target_cell)

      if target_tiles.size == 4 && target_tiles.all? { |t| catalog.tracked?(t.pattern_hash) }
        skip_outcome = catalog_skip_outcome(target_tiles, dir, catalog)
        return skip_outcome if skip_outcome
      end

      TileClassifier.probe_and_classify!(cpu, ppu, apu, keys, mmu, dir, catalog:, screen_name:,
                                                                        stationary_positions:, retries:)
    end

    # nil means "not skippable, still needs a live probe". Two safe positive signals, neither
    # requiring a fully-resolved category: (1) this exact direction was already confirmed passable
    # for every one of the 4 tiles -- reusable regardless of category, including still-:unknown
    # tiles (a ledge only ever tested going :down still safely skips a future :down test); (2)
    # every tile is hypothesized :wall (see TileCatalog#record_blocked!, which never wall-labels a
    # tile with existing passable evidence) -- a wall stays a wall in every direction we'd ever
    # want to enter it from. There is deliberately no "all :walkable -> skip any direction" rule:
    # that would assume symmetry from a single data point, which asymmetric tiles (doors, ledges)
    # disprove.
    def self.catalog_skip_outcome(tiles, dir, catalog)
      entries = tiles.map { |t| catalog.lookup(t.pattern_hash) }
      return :ok if entries.all? { |e| e.passable_from.include?(dir) }
      return :blocked if entries.all? { |e| e.category == :wall }

      nil
    end

    def self.recoverable?(reset, cell, recovery_attempts)
      return false unless reset
      return false if recovery_attempts[cell] >= MAX_RECOVERIES_PER_CELL

      recovery_attempts[cell] += 1
      true
    end
  end
end
