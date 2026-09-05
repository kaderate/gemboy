# frozen_string_literal: true

require_relative 'tilemap_reader'
require_relative 'tile_classifier'
require_relative 'tile_catalog'
require_relative 'screen_grid'

# Builds one screen's directional collision grid (see ScreenGrid), keyed by exact gameplay-cell
# coordinates (see TileClassifier) instead of RoomMap::Recorder's fuzzy pixel-snapped nodes -- no
# SNAP_RADIUS ambiguity. The point: a direction is only physically tested if the target cell's
# tiles aren't already resolvable from the shared TileCatalog (a wall stays a wall, grass stays
# grass), so re-exploring a screen (or one sharing tiles with an already-explored one) costs less
# live testing over time. RoomMap::Recorder is the cross-check: it explores blind, this reads
# tiles first, and the two graphs should agree (see ZELDA_BACKLOG.md).
module Zelda
  module ScreenMap
    # Order matters: this engine has order/approach-dependent collision quirks (see
    # ZELDA_BACKLOG.md's movement model), so testing directions in a different order than
    # RoomMap::Recorder's own default (down, left, right, up) can genuinely change an outcome for
    # the exact same physical cell -- observed cross-validating overworld_front_yard (see
    # ZELDA_BACKLOG.md). Matching RoomMap's order here isn't a fix for the underlying quirk, just
    # keeps the two tools comparable.
    DIRECTIONS = %i[down left right up].freeze
    OPPOSITE = TileClassifier::OPPOSITE
    MAX_RECOVERIES_PER_CELL = 3

    # See ZELDA_BACKLOG.md's RoomMap writeup for why `reset:` (a proc returning a fresh
    # [cpu, ppu, apu, mmu, keys], e.g. reloading a checkpoint) matters: some edges lead to a
    # transition that never resolves within find_link's retry budget. Without `reset` (default),
    # :lost aborts the whole build, matching RoomMap::Recorder's own default behavior.
    # `logger`, if given, is called with one progress string per cell -- a run with no output
    # until the very end can't be told apart from a stalled one (see ZELDA_BACKLOG.md).
    def self.build(cpu, ppu, apu, keys, mmu, screen_name:, catalog:, stationary_positions:, max_cells: 40,
                   retries: 8, reset: nil, stats: nil, logger: nil)
      grid = ScreenGrid.new(screen_name)
      start_pos = find_link(cpu, ppu, apu, mmu, stationary_positions:)
      return [grid, :lost] if start_pos.nil?

      frontier = [TileClassifier.cell_for(start_pos)]
      probed = {}
      recovery_attempts = Hash.new(0)
      t0 = Time.now

      until frontier.empty?
        return [grid, :max_cells] if probed.size >= max_cells

        cell = frontier.shift
        next if probed[cell]

        logger&.call("t=#{(Time.now - t0).round(1)}s cell=#{cell.inspect} probed=#{probed.size}")

        state = [cpu, ppu, apu, mmu, keys]
        result = visit_cell!(state, grid, cell, frontier, probed, catalog:, screen_name:, stationary_positions:,
                                                                  retries:, reset:, recovery_attempts:, stats:)
        return [grid, :lost] if result == :lost

        cpu, ppu, apu, mmu, keys = result
      end
      [grid, :exhausted]
    end

    def self.visit_cell!(state, grid, cell, frontier, probed, catalog:, screen_name:, stationary_positions:, retries:,
                         reset:, recovery_attempts:, stats: nil)
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
                                                                          stationary_positions:, retries:, stats:)
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

    # Tries to resolve `dir` from `cell` purely by catalog lookup (no movement, see
    # TileCatalog#skip_outcome) before falling back to a live TileClassifier probe. Returns
    # :ok/:blocked/:scroll/:lost. `stats`, if given, is a Hash tallied with :skipped/:tested -- how
    # much this screen actually benefited from already-cataloged tiles (see ZELDA_BACKLOG.md).
    def self.resolve_direction!(cpu, ppu, apu, keys, mmu, cell, dir, catalog:, screen_name:, stationary_positions:,
                                retries:, stats: nil)
      target_cell = ScreenGrid.cell_after(cell, dir)
      grid_tiles = Zelda::TilemapReader.visible_grid(ppu, mmu)
      hashes = TileClassifier.tiles_in_cell(grid_tiles, *target_cell).map(&:pattern_hash)

      skip_outcome = hashes.size == 4 ? catalog.skip_outcome(hashes, dir) : nil
      return tally!(stats, :skipped, skip_outcome) if skip_outcome

      tally!(stats, :tested, nil)
      TileClassifier.probe_and_classify!(cpu, ppu, apu, keys, mmu, dir, catalog:, screen_name:,
                                                                        stationary_positions:, retries:)
    end

    def self.tally!(stats, key, return_value)
      stats[key] = stats.fetch(key, 0) + 1 if stats
      return_value
    end

    def self.recoverable?(reset, cell, recovery_attempts)
      return false unless reset
      return false if recovery_attempts[cell] >= MAX_RECOVERIES_PER_CELL

      recovery_attempts[cell] += 1
      true
    end
  end
end
