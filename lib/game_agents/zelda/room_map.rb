# frozen_string_literal: true
# General-purpose room mapper: instead of hand-classifying a room's BG tilemap into a walkable
# grid (which only worked for starting_house and still needed per-room tuning + live corrections,
# see ZELDA_BACKLOG.md's Navigator sections), this builds a map empirically from move_tiles'
# own confirmed outcomes as a script explores -- works identically for any room, no per-room tile
# ID knowledge required, and sidesteps the 16px-cell-vs-~14px-step rounding drift that caused the
# starting-house grid's false positives.
#
# A node is Link's (y, x) position the first time it's visited; positions within SNAP_RADIUS of an
# existing node are treated as the same node (real per-step position varies a few px between
# visits to "the same spot" -- see the movement model's ~14px-not-16px step size). An edge records
# what actually happened attempting one direction from a node: :ok (moved to another node),
# :blocked (confirmed wall after retries), :scroll (large discontinuous jump -- a screen exit,
# not further explorable from here), or :lost (find_link came back nil).
require 'json'
require_relative 'primitives'

module Zelda
  module RoomMap
    SNAP_RADIUS = 10 # px; smaller than one tile step (~14px) so distinct tiles don't collide
    SCROLL_JUMP_THRESHOLD = 40 # px; see movement_model.screen_scroll_detection in world_model.json

    class Recorder
      attr_reader :name, :nodes, :edges

      def initialize(name)
        @name = name
        @nodes = [] # [{id:, y:, x:}]
        @edges = [] # [{from:, to:, direction:, outcome:}]
      end

      def node_id_for(pos)
        existing = @nodes.find { |n| (n[:y] - pos[:y]).abs <= SNAP_RADIUS && (n[:x] - pos[:x]).abs <= SNAP_RADIUS }
        return existing[:id] if existing

        id = @nodes.size
        @nodes << { id:, y: pos[:y], x: pos[:x] }
        id
      end

      # Attempts one tile in `direction` from Link's current position, retrying a blocked result
      # up to `retries` times before trusting it (this room's collision can be order/approach-
      # dependent -- see ZELDA_BACKLOG.md's "Movement model"). Records exactly one edge either way.
      # Returns [outcome, new_position].
      def record_move(cpu, ppu, apu, keys, mmu, direction, stationary_positions:, retries: 3)
        before = find_link(cpu, ppu, apu, mmu, stationary_positions:)
        return %i[lost], nil if before.nil?

        from_id = node_id_for(before)
        outcome = nil
        after = nil
        retries.times do |i|
          moved = move_tiles(cpu, ppu, apu, keys, mmu, direction, 1, stationary_positions:)
          after = find_link(cpu, ppu, apu, mmu, stationary_positions:)
          if after.nil?
            outcome = :lost
            break
          end

          delta = Math.sqrt(((after[:y] - before[:y])**2) + ((after[:x] - before[:x])**2))
          if delta >= SCROLL_JUMP_THRESHOLD
            outcome = :scroll
            break
          elsif moved.positive?
            outcome = :ok
            break
          elsif i == retries - 1
            outcome = :blocked
          end
        end

        to_id = after && outcome != :lost ? node_id_for(after) : nil
        @edges << { from: from_id, to: to_id, direction:, outcome: }
        [outcome, after]
      end

      # Tries all 4 directions from the current position, for unattended frontier-style mapping.
      # Returns the outcomes as {direction => outcome}. Does not move back afterward -- caller
      # decides whether/how to return to a known node (e.g. via the reverse direction).
      def probe_all_directions(cpu, ppu, apu, keys, mmu, stationary_positions:, directions: %i[up down left right])
        directions.each_with_object({}) do |dir, results|
          outcome, _pos = record_move(cpu, ppu, apu, keys, mmu, dir, stationary_positions:)
          results[dir] = outcome
          # Undo a successful move so each direction is tried from the same node (best-effort --
          # the reverse move's own outcome isn't recorded as a separate edge to avoid noise).
          reverse = { up: :down, down: :up, left: :right, right: :left }[dir]
          move_tiles(cpu, ppu, apu, keys, mmu, reverse, 1, stationary_positions:) if outcome == :ok
        end
      end

      def to_h
        { name:, nodes:, edges: }
      end

      def save(path)
        File.write(path, JSON.pretty_generate(to_h))
      end

      def self.load(path)
        data = JSON.parse(File.read(path, encoding: 'UTF-8'), symbolize_names: true)
        recorder = new(data[:name])
        recorder.instance_variable_set(:@nodes, data[:nodes])
        recorder.instance_variable_set(:@edges, data[:edges])
        recorder
      end
    end
  end
end
