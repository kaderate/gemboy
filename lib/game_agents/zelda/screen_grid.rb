# frozen_string_literal: true

require 'json'
require_relative 'tile_classifier'

# One screen's directional collision grid, keyed by exact gameplay-cell coordinates (see
# TileClassifier) -- built by ScreenMap.build, persisted the same way RoomMap::Recorder persists
# its own graph (see data/room_maps/*.json).
module Zelda
  class ScreenGrid
    attr_reader :name, :cells

    def initialize(name)
      @name = name
      @cells = {} # [row, col] => { up:, down:, left:, right: } each nil/:ok/:blocked/:exit
    end

    def edges_for(cell) = (@cells[cell] ||= {})

    def self.cell_after(cell, dir) = TileClassifier.cell_after(cell, dir)
    def cell_after(cell, dir) = self.class.cell_after(cell, dir)

    def neighbors(cell)
      edges_for(cell).filter_map { |dir, outcome| [dir, cell_after(cell, dir)] if outcome == :ok }
    end

    # BFS over confirmed :ok edges only (skip-derived edges count the same as physically tested
    # ones -- both mean "trusted to walk without re-testing").
    def path_to(from, to)
      return [] if from == to

      queue = [[from, []]]
      visited = { from => true }
      until queue.empty?
        current, path = queue.shift
        neighbors(current).each do |dir, nxt|
          next if visited[nxt]

          new_path = path + [dir]
          return new_path if nxt == to

          visited[nxt] = true
          queue << [nxt, new_path]
        end
      end
      nil
    end

    def to_h
      { name:, cells: cells.map { |(row, col), edges| { row:, col:, edges: edges.transform_values(&:to_s) } } }
    end

    def save(path)
      File.write(path, JSON.pretty_generate(to_h))
    end

    def self.load(path)
      data = JSON.parse(File.read(path, encoding: 'UTF-8'), symbolize_names: true)
      grid = new(data[:name])
      data[:cells].each do |c|
        grid.cells[[c[:row], c[:col]]] = c[:edges].transform_values(&:to_sym)
      end
      grid
    end
  end
end
