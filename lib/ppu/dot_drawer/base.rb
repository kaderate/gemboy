# frozen_string_literal: true

class PPU
  module DotDrawer
    class Base
      attr_reader :bg_palette, :obj_palette, :scanline, :sprite_scanner, :tile_cache, :tile_attr_cache

      def initialize(bg_palette:, obj_palette:, scanline:, sprite_scanner:, vram:)
        @bg_palette = bg_palette
        @obj_palette = obj_palette
        @scanline = scanline
        @sprite_scanner = sprite_scanner
        @vram = vram

        @window_line_counter = 0
        @window_used_this_scanline = false

        @tile_cache = {}
        @tile_attr_cache = {}

        reset_caches!
      end

      # The PPU's own internal fetch (SpriteScanner, tile rendering, debug probe) always sees real
      # memory, even while the CPU bus is locked out (see #vram_bus/#oam_bus for that).
      def read_vram(addr, length: 1, bank: 0) = @vram.read(addr, length, bank:)

      def reset_tile_column_caches!
        @tile_cache.clear
        @tile_attr_cache.clear
      end

      def reset_window_line_state!
        @window_line_counter = 0
        @window_used_this_scanline = false
      end

      def update_window_line_counter!
        return unless @window_used_this_scanline

        @window_line_counter += 1
        @window_used_this_scanline = false
      end

      def reset_caches!
        # -1 vs nil: YJIT optimization, keeps Integer type for tile_x cache (tile_x always >= 0)
        @bg_tile_x_cache = -1
        @bg_tile_cache = nil
        @win_tile_x_cache = -1
        @win_tile_cache = nil
        @bg_tile_attr_cache = nil
        @win_tile_attr_cache = nil
      end
    end
  end
end
