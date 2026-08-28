# frozen_string_literal: true

require_relative '../../mmu'

module Debug
  module Probes
    # PPUProbe exposes the state of the PPU to the debugger
    class PPUProbe
      TILE_COUNT = 384
      TILE_BYTES = 16
      TILE_DATA_BEGIN = 0x8000
      TILE_MAP_ADDRS = [0x9800, 0x9C00].freeze
      TILE_MAP_SIZE = 32 * 32
      SPRITE_COUNT = 40
      SPRITE_BYTES = 4

      REGISTER_ADDRS = {
        lcdc: 0xFF40, stat: 0xFF41, scy: 0xFF42, scx: 0xFF43, ly: 0xFF44, lyc: 0xFF45,
        bgp: 0xFF47, obp0: 0xFF48, obp1: 0xFF49, wy: 0xFF4A, wx: 0xFF4B
      }.freeze

      def initialize(ppu:, mmu:)
        @ppu = ppu
        @mmu = mmu
      end

      def snapshot = { mode: @ppu.mode, vram_version: @mmu.vram_version, registers:, tiles:, tilemaps:, oam: }

      private

      # MMU#read_vram and #read_oams bypass the PPU gating on purpose (MMU#read would answer 0xFF during mode 3)
      def registers = REGISTER_ADDRS.transform_values { @mmu.read(_1) }

      def tiles = Array.new(TILE_COUNT) { decode_tile(@mmu.read_vram(TILE_DATA_BEGIN + (_1 * TILE_BYTES), TILE_BYTES)) }

      # Independent from PPU::Tile because no cache and no coupling to column rendering
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

      def tilemaps = TILE_MAP_ADDRS.map { @mmu.read_vram(_1, TILE_MAP_SIZE) }

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
