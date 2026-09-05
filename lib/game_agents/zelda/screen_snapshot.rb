# frozen_string_literal: true

require_relative 'tilemap_reader'
require_relative 'tile_classifier'
require_relative 'tile_catalog'

# Pure-read classification of every gameplay cell currently visible on screen, straight from the
# shared TileCatalog -- no movement, no dependency on what ScreenMap's frontier walk has reached
# yet. This is the "look at the whole screen" half of the navigation overhaul (see
# ZELDA_BACKLOG.md): a screen made mostly of already-cataloged tiles (grass, hedge) gets almost
# fully classified for free, even in cells Link has never walked to.
module Zelda
  module ScreenSnapshot
    CELL_ROWS = TilemapReader::ROWS / 2 # 9
    CELL_COLS = TilemapReader::COLS / 2 # 10

    CellInfo = Struct.new(:row, :col, :hashes, :status, keyword_init: true)

    def self.build(ppu, mmu, catalog)
      grid = TilemapReader.visible_grid(ppu, mmu)
      (0...CELL_ROWS).flat_map do |row|
        (0...CELL_COLS).map do |col|
          hashes = TileClassifier.tiles_in_cell(grid, row, col).map(&:pattern_hash)
          CellInfo.new(row:, col:, hashes:, status: classify(hashes, catalog))
        end
      end
    end

    # :unexplored -- at least one of the cell's 4 tiles has never been seen before, needs a live
    # test. :probably_walkable -- every tile has *some* confirmed passable direction but the
    # catalog hasn't resolved a final category (see TileCatalog); shown distinctly from
    # :walkable (every tile's category is fully resolved) so a human reviewer can tell "likely
    # fine" from "definitely fine" apart at a glance. :mixed_unknown -- all tiles are tracked but
    # disagree in a way none of the other rules cover; flagged for review rather than guessed.
    def self.classify(hashes, catalog)
      return :unexplored unless hashes.all? { |h| catalog.tracked?(h) }

      entries = hashes.map { |h| catalog.lookup(h) }
      categories = entries.map(&:category)
      %i[wall door water ledge hole decorative].each { |c| return c if categories.include?(c) }
      return :walkable if categories.all?(:walkable)
      return :probably_walkable if entries.all? { |e| !e.passable_from.empty? }

      :mixed_unknown
    end
  end
end
