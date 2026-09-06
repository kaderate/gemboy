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
    # ZELDA_BACKLOG.md's movement model) -- a different order than RoomMap::Recorder's own default
    # can change the outcome for the exact same cell. Matching RoomMap's order isn't a fix, just
    # keeps the two tools comparable.
    DIRECTIONS = %i[down left right up].freeze
    MAX_RECOVERIES_PER_CELL = 6

    # `reset:` (a proc returning a fresh [cpu, ppu, apu, mmu, keys]) matters: some edges lead to a
    # transition that never resolves within find_link's retry budget (see ZELDA_BACKLOG.md's
    # RoomMap writeup). Without it (default), :lost aborts the whole build. With it, a cell that
    # exhausts MAX_RECOVERIES_PER_CELL is dropped (and logged) instead of sinking the rest of the
    # frontier -- one recalcitrant cell (a wandering NPC in the way, say) shouldn't cost every
    # other cell already resolved (see ZELDA_BACKLOG.md's overworld_screen3 finding). `logger`, if
    # given, is called with one progress string per cell -- silence until the very end looks like a
    # stall.
    # `on_grid_ready`, if given, is called once with `grid` right after it's created -- a full
    # exploration can run for tens of minutes, and the grid/catalog only reach the caller's own
    # save logic on a normal return, so a hard kill (a wall-clock `timeout` wrapper included --
    # see ZELDA_BACKLOG.md) mid-build loses everything since the last save. Handing the caller a
    # live reference lets it register a signal trap that saves the real in-progress state instead.
    def self.build(cpu, ppu, apu, keys, mmu, screen_name:, catalog:, stationary_positions:, max_cells: 40,
                   retries: 8, reset: nil, stats: nil, logger: nil, on_grid_ready: nil)
      grid = ScreenGrid.new(screen_name)
      on_grid_ready&.call(grid)
      start_pos = find_link(cpu, ppu, apu, mmu, stationary_positions:)
      return [grid, :lost] if start_pos.nil?

      frontier = [TileClassifier.cell_for(start_pos)]
      probed = {}
      recovery_attempts = Hash.new(0)
      live_probed = {}
      t0 = Time.now

      until frontier.empty?
        return [grid, :max_cells] if probed.size >= max_cells

        cell = frontier.shift
        next if probed[cell]

        logger&.call("t=#{(Time.now - t0).round(1)}s cell=#{cell.inspect} probed=#{probed.size}")

        state = [cpu, ppu, apu, mmu, keys]
        result = visit_cell!(state, grid, cell, frontier, probed, catalog:, screen_name:, stationary_positions:,
                                                                  retries:, reset:, recovery_attempts:, live_probed:,
                                                                  stats:)
        return [grid, :lost] if result == :lost

        if result.first == :skip
          # A cell that exhausts its own recovery budget doesn't have to sink the whole screen --
          # `reset` already proved we can get back to a known-good state, so drop just this one
          # cell (and whatever's only reachable through it) and keep exploring the rest of the
          # frontier (see ZELDA_BACKLOG.md's overworld_screen3 finding: a single hard cell used to
          # discard 27 perfectly good ones alongside it).
          logger&.call("t=#{(Time.now - t0).round(1)}s cell=#{cell.inspect} SKIPPED")
          cpu, ppu, apu, mmu, keys = result[1..]
          next
        end

        cpu, ppu, apu, mmu, keys = result
      end
      [grid, :exhausted]
    end

    def self.visit_cell!(state, grid, cell, frontier, probed, catalog:, screen_name:, stationary_positions:, retries:,
                         reset:, recovery_attempts:, live_probed:, stats: nil)
      cpu, ppu, apu, mmu, keys = state
      path = navigate_to(cpu, ppu, apu, keys, mmu, grid, cell, stationary_positions:)
      reached = path != :lost && TileClassifier.walk_path!(cpu, ppu, apu, keys, mmu, path, stationary_positions:, retries:)
      unless reached
        return :lost unless reset
        return skip_result(reset, probed, cell) unless recoverable?(recovery_attempts, cell)

        frontier << cell
        return reset.call
      end
      probed[cell] = true

      DIRECTIONS.each do |dir|
        next if grid.edges_for(cell)[dir]

        result = explore_direction!([cpu, ppu, apu, mmu, keys], grid, cell, dir, frontier, probed,
                                    catalog:, screen_name:, stationary_positions:, retries:, reset:,
                                    recovery_attempts:, live_probed:, stats:)
        return result if result == :lost || result.first == :skip

        cpu, ppu, apu, mmu, keys = result
      end
      [cpu, ppu, apu, mmu, keys]
    end

    # Resolves one direction from `cell`, retrying via `reset` on failure until it either succeeds or its
    # own recovery budget is exhausted. Budgeted PER DIRECTION (not per cell, keyed [cell, dir] in
    # `recovery_attempts`) -- a single direction that's deterministically unresolvable (the same corner
    # redirect every reset, see ZELDA_BACKLOG.md's starting_house finding) used to burn through the whole
    # cell's recovery budget via a shared counter, starving the other three directions DIRECTIONS' fixed
    # down-first order never got to try. Returns the (possibly reset) state array on success or give-up,
    # :lost if `reset` is unavailable, or a skip_result array if recovery can't even get back to `cell`.
    def self.explore_direction!(state, grid, cell, dir, frontier, probed, catalog:, screen_name:,
                                stationary_positions:, retries:, reset:, recovery_attempts:, live_probed:, stats:)
      cpu, ppu, apu, mmu, keys = state
      loop do
        outcome = resolve_direction!(cpu, ppu, apu, keys, mmu, cell, dir, catalog:, screen_name:,
                                                                          stationary_positions:, retries:, live_probed:,
                                                                          stats:)
        unless outcome == :lost
          apply_outcome!(cpu, ppu, apu, keys, mmu, grid, cell, dir, outcome, frontier, probed,
                         stationary_positions:, retries:)
          return [cpu, ppu, apu, mmu, keys] if TileClassifier.at_cell?(cpu, ppu, apu, mmu, cell, stationary_positions:)
        end

        # :lost, or walk_back_to_cell! (inside apply_outcome!) still failed after its own retry budget --
        # genuinely stuck away from `cell`, not just the deterministic creep a same-seed reset would
        # reproduce identically (see ZELDA_BACKLOG.md's movement model).
        return :lost unless reset

        give_up_on_dir = !recoverable?(recovery_attempts, [cell, dir])
        cpu, ppu, apu, mmu, keys = reset.call
        path_back = navigate_to(cpu, ppu, apu, keys, mmu, grid, cell, stationary_positions:)
        reached_back = path_back != :lost &&
                       TileClassifier.walk_path!(cpu, ppu, apu, keys, mmu, path_back, stationary_positions:, retries:)
        return skip_result(reset, probed, cell) unless reached_back

        return [cpu, ppu, apu, mmu, keys] if give_up_on_dir
      end
    end

    def self.skip_result(reset, probed, cell)
      probed.delete(cell)
      [:skip, *reset.call]
    end

    def self.apply_outcome!(cpu, ppu, apu, keys, mmu, grid, cell, dir, outcome, frontier, probed, stationary_positions:,
                            retries:)
      case outcome
      when :scroll then grid.edges_for(cell)[dir] = :exit
      when :blocked then grid.edges_for(cell)[dir] = :blocked
      when :ok
        grid.edges_for(cell)[dir] = :ok
        new_cell = grid.cell_after(cell, dir)
        frontier << new_cell unless probed[new_cell]
      end
      TileClassifier.walk_back_to_cell!(cpu, ppu, apu, keys, mmu, grid, cell, dir, stationary_positions:, retries:)
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
    #
    # `live_probed` gates the skip lookup on `cell` having at least one directly-tested (not
    # catalog-derived) CONFIRMED edge of its own already -- :lost doesn't count, only :ok/
    # :blocked/:scroll do. `skip_outcome` only ever looks at the TARGET cell's tile pattern, never
    # at `cell` itself -- so a position-specific collision quirk near `cell` (a diagonal corner-
    # redirect, say) has nothing to do with the tile being entered and can get silently overridden
    # by an unrelated cell elsewhere that happens to share the same tile pattern and already
    # tested clean (see ZELDA_BACKLOG.md's starting_house finding: a fully catalog-skipped
    # rebuild, zero live tests anywhere, wrongly resolved `[3,3] -> :down` as `:ok` when a live
    # SCX/SCY-verified probe had already proven it a real `:lost` redirect). Forcing every cell's
    # first-ever direction to be live (DIRECTIONS' fixed order makes that `:down` in practice)
    # means the exact class of quirk that bit `[3,3]` always gets a genuine local check before any
    # of that cell's OTHER directions are allowed to trust the catalog. Marking on ANY live
    # attempt (including :lost) instead of only a confirmed one was an earlier, buggier version of
    # this gate: `explore_direction!`'s own recovery loop retries the exact same [cell, dir] after
    # a reset, and a :lost first attempt would then let the retry fall straight into the very
    # skip_outcome this gate exists to block, right back to the wrong `:ok` -- confirmed live: a
    # rebuild with that version still resolved `[3,3] -> :down` as `:ok` (stats showed 17 real
    # tests, so the gate wasn't fully bypassed, just defeated on this exact cell/direction) while
    # an isolated `TileClassifier.probe` on the same checkpoint kept confirming `:lost`.
    def self.resolve_direction!(cpu, ppu, apu, keys, mmu, cell, dir, catalog:, screen_name:, stationary_positions:,
                                retries:, live_probed:, stats: nil)
      target_cell = ScreenGrid.cell_after(cell, dir)
      grid_tiles = Zelda::TilemapReader.visible_grid(ppu, mmu)
      hashes = TileClassifier.tiles_in_cell(grid_tiles, *target_cell).map(&:pattern_hash)

      if live_probed[cell] && hashes.size == 4
        skip_outcome = catalog.skip_outcome(hashes, dir)
        return tally!(stats, :skipped, skip_outcome) if skip_outcome
      end

      tally!(stats, :tested, nil)
      outcome = TileClassifier.probe_and_classify!(cpu, ppu, apu, keys, mmu, dir, catalog:, screen_name:,
                                                                                  stationary_positions:, retries:)
      live_probed[cell] = true unless outcome == :lost
      outcome
    end

    def self.tally!(stats, key, return_value)
      stats[key] = stats.fetch(key, 0) + 1 if stats
      return_value
    end

    def self.recoverable?(recovery_attempts, cell)
      return false if recovery_attempts[cell] >= MAX_RECOVERIES_PER_CELL

      recovery_attempts[cell] += 1
      true
    end

    # The payoff of a built ScreenGrid over RoomMap::Recorder's bump-and-retry exploration: get
    # from wherever Link currently is to `target_cell` purely by reading the map, no live probing
    # at all. Returns false (without moving) if there's no known path or Link can't be found; the
    # caller decides whether that's worth a fresh probe or a reset.
    def self.navigate!(cpu, ppu, apu, keys, mmu, grid, target_cell, stationary_positions:, retries: 12)
      pos = find_link(cpu, ppu, apu, mmu, stationary_positions:)
      return false if pos.nil?

      current_cell = TileClassifier.cell_for(pos)
      return true if current_cell == target_cell

      path = grid.path_to(current_cell, target_cell)
      return false if path.nil?

      TileClassifier.walk_path!(cpu, ppu, apu, keys, mmu, path, stationary_positions:, retries:)
    end
  end
end
