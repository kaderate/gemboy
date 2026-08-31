# frozen_string_literal: true

require_relative 'base'

class PPU
  module DotDrawer
    class CGB < Base
      def draw_current_dot(screen_x, screen_y)
        # CGB LCDC.0: when 0, bg/window are disabled, only BGP 0 is displayed (sprites visible behind)
        bg_color = begin
          window_x = screen_x - (scanline.wx - 7)
          if scanline.window_enabled && screen_y >= scanline.wy && window_x >= 0
            @window_used_this_scanline = true
            compute_window_pixel(window_x)
          else
            compute_background_pixel(screen_x, screen_y)
          end
        end

        sprite_pixel_color, sprite_pixel_priority, sprite_palette = sprite_scanner.sprite_pixel_cache[screen_x]

        if !sprite_pixel_color || (scanline.bg_enabled && sprite_pixel_priority == 1 && bg_color != 0)
          bg_palette.color(palette: @palette_cache, index: bg_color)
        else
          obj_palette.color(palette: sprite_palette, index: sprite_pixel_color)
        end
      end

      def compute_background_pixel(screen_x, screen_y)
        bg_x = (screen_x + scanline.scx) % BACKGROUND_WIDTH
        bg_y = (screen_y + scanline.scy) % BACKGROUND_HEIGHT
        tile_x = bg_x / 8

        if tile_x != @bg_tile_x_cache
          @bg_tile_x_cache = tile_x
          tile_y = bg_y / 8

          # A bit of a mess here. First, read tile index from VRAM: always in bank 0. This index is used to read:
          #  - tile data: always bank 0 for DMG, "tile attribute bank" for CGB
          #  - tile attrbute: always bank 1 (CGB only), contains "bank" used to read tile data
          vram_addr  = scanline.bg_tile_map_addr + (tile_y * 32) + tile_x
          tile_index = read_vram(vram_addr)

          @bg_tile_attr_cache = tile_attr_cache[vram_addr] ||= read_vram(vram_addr, bank: 1)
          @palette_cache = @bg_tile_attr_cache & 0x7
          data_bank = (@bg_tile_attr_cache >> 3) & 0x1

          tile_addr = scanline.tile_addr(tile_index)
          cache_key = [data_bank, tile_addr]
          @bg_tile_cache = tile_cache[cache_key] ||= Tile.new(data: read_vram(tile_addr, length: 16, bank: data_bank))
        end

        y_in_tile = Coordinate.flip(bg_y % 8, @bg_tile_attr_cache.allbits?(1 << 6))
        x_in_tile = Coordinate.flip(bg_x % 8, @bg_tile_attr_cache.allbits?(1 << 5))
        @bg_tile_cache.pixel_color_index(x_in_tile, y_in_tile)
      end

      def compute_window_pixel(win_x)
        win_y = @window_line_counter
        tile_x = win_x / 8

        if tile_x != @win_tile_x_cache
          @win_tile_x_cache = tile_x
          tile_y = win_y / 8
          vram_addr = scanline.window_tile_map_addr + (tile_y * 32) + tile_x
          tile_index = read_vram(vram_addr)

          @win_tile_attr_cache = tile_attr_cache[vram_addr] ||= read_vram(vram_addr, bank: 1)
          @palette_cache = @win_tile_attr_cache & 0x7
          data_bank = (@win_tile_attr_cache >> 3) & 0x1

          tile_addr = scanline.tile_addr(tile_index)
          cache_key = [data_bank, tile_addr]
          @win_tile_cache = tile_cache[cache_key] ||= Tile.new(data: read_vram(tile_addr, length: 16, bank: data_bank))
        end

        y_in_tile = Coordinate.flip(win_y % 8, @win_tile_attr_cache.allbits?(1 << 6))
        x_in_tile = Coordinate.flip(win_x % 8, @win_tile_attr_cache.allbits?(1 << 5))
        @win_tile_cache.pixel_color_index(x_in_tile, y_in_tile)
      end
    end
  end
end
