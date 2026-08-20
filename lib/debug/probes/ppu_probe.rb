# frozen_string_literal: true

require_relative '../../mmu'

module Debug
  module Probes
    class PpuProbe
      TILE_COUNT = 384
      TILE_BYTES = 16
      TILE_DATA_BEGIN = 0x8000
      TILE_MAP_ADDRS = [0x9800, 0x9C00].freeze
      TILE_MAP_SIZE = 32 * 32
      SPRITE_COUNT = 40
      SPRITE_BYTES = 4

      REGISTER_ADDRS = {
        lcdc: MMU::ADDR_LCDC, stat: MMU::ADDR_LCD_STAT, ly: MMU::ADDR_LY, lyc: MMU::ADDR_LYC,
        scx: MMU::ADDR_SCX, scy: MMU::ADDR_SCY, wx: MMU::ADDR_WX, wy: MMU::ADDR_WY,
        bgp: MMU::ADDR_BGP, obp0: MMU::ADDR_OBP0, obp1: MMU::ADDR_OBP1
      }.freeze

      def initialize(ppu:, mmu:)
        @ppu = ppu
        @mmu = mmu
      end

      def snapshot
        { mode: @ppu.mode, vram_version: @mmu.vram_version, registers:, tiles:, tilemaps:, oam: }
      end

      private

      # MMU#read_vram and #read_oams bypass the PPU accessibility gate on purpose: MMU#read
      # would answer 0xFF during mode 3.
      def registers
        REGISTER_ADDRS.transform_values { @mmu.read(_1) }
      end

      def tiles
        Array.new(TILE_COUNT) { decode_tile(@mmu.read_vram(TILE_DATA_BEGIN + (_1 * TILE_BYTES), TILE_BYTES)) }
      end

      # Deliberately independent from PPU::Tile: no cache, no coupling to column rendering.
      def decode_tile(bytes)
        pixels = Array.new(64, 0)
        8.times do |row|
          low = bytes[row * 2]
          high = bytes[(row * 2) + 1]
          8.times do |col|
            bit = 7 - col
            pixels[(row * 8) + col] = (((high >> bit) & 1) << 1) | ((low >> bit) & 1)
          end
        end
        pixels
      end

      def tilemaps
        TILE_MAP_ADDRS.map { @mmu.read_vram(_1, TILE_MAP_SIZE) }
      end

      def oam
        bytes = @mmu.read_oams
        Array.new(SPRITE_COUNT) do |index|
          base = index * SPRITE_BYTES
          { y: bytes[base], x: bytes[base + 1], tile: bytes[base + 2], flags: bytes[base + 3] }
        end
      end
    end
  end
end
