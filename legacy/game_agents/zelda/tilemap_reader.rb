# frozen_string_literal: true

require 'digest'
require_relative '../../ppu/tile'
require_relative '../../ppu/coordinate'

# Reads the BG layer's visible tilemap directly from VRAM, mirroring exactly what the renderer
# itself computes per-pixel (see PPU::DotDrawer::CGB#compute_background_pixel / ::DMG's own
# variant) but for the whole visible 20x18 grid at once and with no side effects on live emulator
# state (no VBK writes -- ppu.vram exposes bank-parameterized reads directly). This is the "look
# at the screen" half of the tile-catalog approach: HudReader already does this for the window
# layer (HUD); this is the BG-layer equivalent, needed to see the actual walkable terrain rather
# than move-and-observe.
#
# Mode-dependent: despite the ROM's "_dx.gbc" filename, `mmu.model.cgb?` is actually false for it
# at boot (no --cgb flag forcing CGB on this dual-compatible cartridge, see CLAUDE.md's model
# selection rule) -- it runs in plain DMG mode, which has no per-tile attribute byte at all (no
# bank/palette/flip -- see PPU::DotDrawer::DMG#compute_background_pixel, a single global BGP
# register colors every tile). Reading VRAM bank 1 on a DMG @vram (allocated with bank: 1, i.e.
# one bank total) silently returns nil, not an error -- checking cgb? explicitly avoids that trap.
module Zelda
  module TilemapReader
    TILE_DATA_ADDRS = [0x8000, 0x9000].freeze
    TILE_MAP_ADDRS = [0x9800, 0x9C00].freeze
    TILE_PX = 8
    COLS = PPU::WINDOW_WIDTH / TILE_PX  # 20
    ROWS = PPU::WINDOW_HEIGHT / TILE_PX # 18

    TileInfo = Struct.new(:screen_row, :screen_col, :tile_index, :bank, :palette, :xflip, :yflip,
                          :priority, :pattern_hash, keyword_init: true)

    # Signed/unsigned tile addressing, same rule as Scanline#tile_addr (see lib/ppu/scanline.rb) --
    # duplicated rather than shared because that method lives on a live per-scanline render object,
    # not something meant to be called standalone outside the render loop.
    def self.tile_addr(tile_data_addr, tile_index)
      return tile_data_addr + (tile_index * 16) if tile_data_addr == TILE_DATA_ADDRS[0]

      tile_data_addr + ((tile_index < 128 ? tile_index : tile_index - 256) * 16)
    end

    # Hashes the tile's actual pixel data + palette (not its raw tile_index, which is only stable
    # within one VRAM bank/tile-data-addressing combination, and not its bank/flip flags, which
    # are rendering details that don't change what the tile *is* for navigation purposes) -- this
    # is the stable key TileCatalog persists classifications under, so the same visual tile (e.g.
    # grass) is recognized as the same catalog entry on every future screen.
    def self.pattern_hash(pixel_bytes, palette)
      Digest::MD5.hexdigest(pixel_bytes.pack('C*') + palette.to_s)
    end

    # Returns a flat array of ROWS*COLS TileInfo, one per currently-visible screen tile (row-major,
    # screen_row/screen_col in tile units, i.e. screen pixel = (screen_col*8, screen_row*8)).
    def self.visible_grid(ppu, mmu)
      lcdc = ppu.lcd_control
      bg_tile_map_addr = lcdc.bg_tile_map_display_select ? TILE_MAP_ADDRS[1] : TILE_MAP_ADDRS[0]
      tile_data_addr = lcdc.bg_and_window_tile_data_select ? TILE_DATA_ADDRS[0] : TILE_DATA_ADDRS[1]
      scx = mmu.read(0xFF43)
      scy = mmu.read(0xFF42)
      cgb = mmu.model.cgb?

      (0...ROWS).flat_map do |screen_row|
        (0...COLS).map do |screen_col|
          tile_info(ppu, bg_tile_map_addr, tile_data_addr, scx, scy, screen_row, screen_col, cgb)
        end
      end
    end

    def self.tile_info(ppu, bg_tile_map_addr, tile_data_addr, scx, scy, screen_row, screen_col, cgb)
      bg_x = ((screen_col * TILE_PX) + scx) % PPU::BACKGROUND_WIDTH
      bg_y = ((screen_row * TILE_PX) + scy) % PPU::BACKGROUND_HEIGHT
      tile_x = bg_x / TILE_PX
      tile_y = bg_y / TILE_PX
      vram_addr = bg_tile_map_addr + (tile_y * 32) + tile_x

      tile_index = ppu.vram.read(vram_addr, 1, bank: 0)

      if cgb
        attr = ppu.vram.read(vram_addr, 1, bank: 1)
        palette = attr & 0x7
        data_bank = (attr >> 3) & 0x1
        xflip = attr.anybits?(0x20)
        yflip = attr.anybits?(0x40)
        priority = attr.anybits?(0x80)
      else
        palette = 0
        data_bank = 0
        xflip = false
        yflip = false
        priority = false
      end

      pixel_bytes = ppu.vram.read(tile_addr(tile_data_addr, tile_index), 16, bank: data_bank)

      TileInfo.new(screen_row:, screen_col:, tile_index:, bank: data_bank, palette:, xflip:, yflip:,
                   priority:, pattern_hash: pattern_hash(pixel_bytes, palette))
    end

    # Decodes the tile's actual pixel colors (0-3, palette indices) as an 8x8 grid, respecting
    # flip flags -- for visual audit (ASCII dump next to a screenshot) rather than gameplay logic.
    def self.pixel_grid(ppu, tile_info, tile_data_addr)
      pixel_bytes = ppu.vram.read(tile_addr(tile_data_addr, tile_info.tile_index), 16, bank: tile_info.bank)
      tile = PPU::Tile.new(data: pixel_bytes)
      Array.new(TILE_PX) do |y|
        Array.new(TILE_PX) do |x|
          tile.pixel_color_index(PPU::Coordinate.flip(x, tile_info.xflip), PPU::Coordinate.flip(y, tile_info.yflip))
        end
      end
    end
  end
end
