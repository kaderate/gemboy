# frozen_string_literal: true
# Reads the HUD (hearts, rupee counter) directly from the window-layer tilemap instead of hunting
# a WRAM address -- the HUD is drawn via the window layer (LCDC bit 5, confirmed enabled; WY=128
# puts it at the bottom 2 tile rows, WX=7 i.e. window x=0 so tile columns map 1:1 to screen
# columns) at a fixed, unscrolled tilemap base, so a straight tile read is simpler and more
# directly verifiable than a memory-diff hunt.
#
# Only tile IDs actually observed are treated as known. FULL_HEART_TILE (0xa9) and DIGIT_TILES[0]
# (0xb0) are confirmed from a real HUD read. Empty/half-heart tiles and digits 1-9 have NOT been
# observed (would need Link to take damage or the rupee count to change past 0, neither of which
# has happened in this session) -- reading an unrecognized tile in these regions reports :unknown
# rather than guessing a value, per this project's grounded-data discipline (see ZELDA_AGENT.md).
module Zelda
  module HudReader
    WINDOW_TILEMAP_ROW0 = 0 # window-relative tile row for the top HUD line (hearts, rupee icon)
    WINDOW_TILEMAP_ROW1 = 1 # bottom HUD line (rupee digits)
    HEART_REGION_COLS = (12..19).freeze # scanned wide since heart containers can grow the count

    FULL_HEART_TILE = 0xa9
    DIGIT_TILES = { 0xb0 => '0' }.freeze # digits 1-9 not yet observed

    def self.window_tilemap_base(mmu)
      lcdc = mmu.read(0xFF40)
      lcdc[6] == 1 ? 0x9C00 : 0x9800
    end

    def self.window_tile(mmu, row, col)
      mmu.read(window_tilemap_base(mmu) + (row * 32) + col)
    end

    # Returns { full: n, unknown: [{col:, tile:}, ...] } -- `unknown` is never silently dropped,
    # so a caller can tell "3 known full hearts" apart from "3 hearts, one of an unseen kind".
    def self.hearts(mmu)
      full = 0
      unknown = []
      HEART_REGION_COLS.each do |col|
        tile = window_tile(mmu, WINDOW_TILEMAP_ROW0, col)
        next if tile == 0x7f # confirmed blank/spacer filler tile, not a heart slot

        if tile == FULL_HEART_TILE
          full += 1
        else
          unknown << { col:, tile: }
        end
      end
      { full:, unknown: }
    end

    # Returns the rupee count as a string of digit characters, or nil at the first unrecognized
    # digit tile (with the raw tiles attached) rather than guessing.
    def self.rupees(mmu, cols: 10..12)
      digits = cols.map { |col| window_tile(mmu, WINDOW_TILEMAP_ROW1, col) }
      chars = digits.map { |t| DIGIT_TILES[t] }
      return { value: chars.join, raw_tiles: digits } if chars.all?

      { value: nil, raw_tiles: digits, note: 'one or more digit tiles not yet in DIGIT_TILES' }
    end
  end
end
