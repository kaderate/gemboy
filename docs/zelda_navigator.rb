# frozen_string_literal: true
# Isolated navigation procedure for the Zelda-agent spike (see docs/ZELDA_AGENT.md's Navigator
# design). Plans a path on a static walkable-tile grid instead of hand-picked direction sequences,
# so a cluttered room's collision geometry (walls, furniture) is routed around rather than
# discovered by bumping into it order-dependently -- see ZELDA_BACKLOG.md's "Movement model"
# section for why the underlying move_tiles primitive is now precise enough to make this reliable.
require 'json'
require_relative 'zelda_primitives'

module Navigator
  DIRECTIONS = { up: [-1, 0], down: [1, 0], left: [0, -1], right: [0, 1] }.freeze

  def self.load_grid(path)
    JSON.parse(File.read(path, encoding: 'UTF-8'))
  end

  def self.save_grid(grid_data, path)
    File.write(path, JSON.pretty_generate(grid_data))
  end

  # Rounds to the nearest cell rather than truncating -- Link's position right after a scripted
  # placement (e.g. post-dialogue) isn't always exactly grid-aligned (observed: a start position
  # landing at row 2.25, not an integer, while NPC positions always landed exactly on-grid). A
  # floor here can put Link's computed cell one row/col off from where he visually is.
  def self.oam_to_cell(y, x, grid_data)
    offset = grid_data['oam_to_cell_offset']
    size = grid_data['cell_size_px']
    [((y + offset['y']).to_f / size).round, ((x + offset['x']).to_f / size).round]
  end

  # If the computed cell is blocked in the grid (alignment slop, not a real obstacle -- Link is
  # standing there), fall back to whichever walkable cell in its immediate neighborhood is
  # closest, so pathfinding doesn't spuriously fail or poison the grid from a bad start read.
  def self.nearest_walkable(grid, cell)
    return cell if grid[cell[0]] && grid[cell[0]][cell[1]]

    rows = grid.size
    cols = grid.first.size
    candidates = []
    (-1..1).each do |dr|
      (-1..1).each do |dc|
        r, c = cell[0] + dr, cell[1] + dc
        candidates << [r, c] if r.between?(0, rows - 1) && c.between?(0, cols - 1) && grid[r][c]
      end
    end
    candidates.min_by { |r, c| (r - cell[0]).abs + (c - cell[1]).abs } || cell
  end

  # BFS (unweighted grid, equal step cost) from start to any cell adjacent to target_cell.
  # start is always treated as walkable (Link is standing there, so it must be) even if the
  # static grid's own classification says otherwise (edge-of-cell measurement slop).
  def self.bfs_path(grid, start, target_cell)
    rows = grid.size
    cols = grid.first.size
    goal_cells = DIRECTIONS.values.map { |dy, dx| [target_cell[0] + dy, target_cell[1] + dx] }
                            .select { |r, c| r.between?(0, rows - 1) && c.between?(0, cols - 1) }
    return [start] if goal_cells.include?(start)

    queue = [start]
    came_from = { start => nil }
    until queue.empty?
      current = queue.shift
      return reconstruct(came_from, current) if goal_cells.include?(current)

      DIRECTIONS.each_value do |dy, dx|
        nxt = [current[0] + dy, current[1] + dx]
        next unless nxt[0].between?(0, rows - 1) && nxt[1].between?(0, cols - 1)
        next unless grid[nxt[0]][nxt[1]]
        next if came_from.key?(nxt)

        came_from[nxt] = current
        queue << nxt
      end
    end
    nil # no path found
  end

  def self.reconstruct(came_from, cell)
    path = [cell]
    path.unshift(cell = came_from[cell]) while came_from[cell]
    path
  end

  # Collapses a cell path into (direction, count) runs, minimizing move_tiles calls.
  def self.compress_path(cells)
    runs = []
    (1...cells.size).each do |i|
      dy = cells[i][0] - cells[i - 1][0]
      dx = cells[i][1] - cells[i - 1][1]
      direction = DIRECTIONS.key([dy, dx])
      raise "non-adjacent path step #{cells[i - 1]} -> #{cells[i]}" unless direction

      if runs.last && runs.last[0] == direction
        runs.last[1] += 1
      else
        runs << [direction, 1]
      end
    end
    runs
  end

  # Executes a path plan run-by-run, verifying real displacement after each run (closed loop --
  # see ZELDA_AGENT.md). This room's collision has an order/approach-dependent quirk (a request
  # can bump differently depending on prior movement, not just the static geometry -- see
  # ZELDA_BACKLOG.md), so a single shortfall is retried in place (same cell, same direction)
  # before it's trusted as a real obstacle and blacklisted -- one noisy sample shouldn't poison
  # the persisted grid and wall off a cell that's actually fine from a different approach.
  def self.reach(cpu, ppu, apu, keys, mmu, target_cell:, grid_data:, grid_path:, stationary_positions:, max_replans: 8, retries_per_run: 2)
    max_replans.times do
      grid = grid_data['grid']
      link_pos = find_link(cpu, ppu, apu, mmu, stationary_positions: stationary_positions)
      return { status: :lost, final_position: nil } if link_pos.nil?

      start_cell = nearest_walkable(grid, oam_to_cell(link_pos[:y], link_pos[:x], grid_data))
      path = bfs_path(grid, start_cell, target_cell)

      # The rounded cell can land on a real-but-poorly-connected cell (e.g. an island created by
      # play corrections near a boundary) even though Link is actually standing just next to a
      # well-connected one. Before giving up, retry from each immediate neighbor.
      if path.nil?
        rows = grid.size
        cols = grid.first.size
        neighbor_path = DIRECTIONS.values.filter_map do |dy, dx|
          r, c = start_cell[0] + dy, start_cell[1] + dx
          next unless r.between?(0, rows - 1) && c.between?(0, cols - 1) && grid[r][c]

          bfs_path(grid, [r, c], target_cell)
        end.min_by(&:size)
        path = neighbor_path if neighbor_path
      end

      return { status: :no_path, final_position: link_pos } if path.nil?
      return { status: :success, final_position: link_pos } if path.size == 1

      runs = compress_path(path)
      cursor = path.first
      replan = false
      runs.each do |direction, count|
        remaining = count
        dy, dx = DIRECTIONS[direction]
        retries_per_run.times do |attempt|
          moved = move_tiles(cpu, ppu, apu, keys, mmu, direction, remaining, stationary_positions: stationary_positions)
          cursor = [cursor[0] + (dy * moved), cursor[1] + (dx * moved)]
          remaining -= moved
          break if remaining.zero?
          next if attempt < retries_per_run - 1 # try the same shortfall again before giving up on it

          blocked_cell = [cursor[0] + dy, cursor[1] + dx]
          if blocked_cell[0].between?(0, grid.size - 1) && blocked_cell[1].between?(0, grid.first.size - 1)
            grid[blocked_cell[0]][blocked_cell[1]] = false
            grid_data['corrections_from_play'] << { 'cell' => blocked_cell, 'result' => 'blocked', 'note' => "move_tiles stopped short here after #{retries_per_run} attempts" }
            save_grid(grid_data, grid_path)
          end
        end
        if remaining.positive?
          replan = true
          break
        end
      end
      next if replan
    end
    { status: :max_replans_exceeded, final_position: find_link(cpu, ppu, apu, mmu, stationary_positions: stationary_positions) }
  end
end
