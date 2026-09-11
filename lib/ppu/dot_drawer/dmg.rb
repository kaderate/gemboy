# frozen_string_literal: true

require_relative 'base'

class PPU
  module DotDrawer
    class DMG < Base
      def draw_current_dot(screen_x, screen_y)
        # DMG LCDC.0: when disabled, neither the background nor the window are drawn (sprites visible behind, only BGP 0)
        bg_color =
          if scanline.bg_enabled
            window_x = screen_x - (scanline.wx - 7)
            if scanline.window_enabled && screen_y >= scanline.wy && window_x >= 0
              @window_used_this_scanline = true
              compute_window_pixel(window_x)
            else
              compute_background_pixel(screen_x, screen_y)
            end
          else
            0
          end

        sprite_pixel = sprite_scanner.sprite_pixel_cache[screen_x]

        if !sprite_pixel || (sprite_pixel[1] == 1 && bg_color != 0)
          index_to_color(scanline.bg_palette[bg_color])
        else
          obj_palette = sprite_pixel[2] == 1 ? scanline.obj_palette1 : scanline.obj_palette0
          index_to_color(obj_palette[sprite_pixel[0]])
        end
      end

      def index_to_color(index) = COLOR_RGBA_SDL.fetch(index)

      def compute_background_pixel(screen_x, screen_y)
        bg_x = (screen_x + scanline.scx) % BACKGROUND_WIDTH
        bg_y = (screen_y + scanline.scy) % BACKGROUND_HEIGHT
        tile_x = bg_x / 8

        if tile_x != @bg_tile_x_cache
          @bg_tile_x_cache = tile_x
          tile_y = bg_y / 8

          vram_addr  = scanline.bg_tile_map_addr + (tile_y * 32) + tile_x
          tile_index = read_vram(vram_addr)
          tile_addr = scanline.tile_addr(tile_index)

          @bg_tile_cache = tile_cache[tile_addr] ||= Tile.new(data: read_vram(tile_addr, length: 16))
        end

        @bg_tile_cache.pixel_color_index(bg_x % 8, bg_y % 8)
      end

      def compute_window_pixel(win_x)
        win_y = @window_line_counter
        tile_x = win_x / 8

        if tile_x != @win_tile_x_cache
          @win_tile_x_cache = tile_x
          tile_y = win_y / 8
          vram_addr = scanline.window_tile_map_addr + (tile_y * 32) + tile_x
          tile_index = read_vram(vram_addr)
          tile_addr = scanline.tile_addr(tile_index)

          @win_tile_cache = tile_cache[tile_addr] ||= Tile.new(data: read_vram(tile_addr, length: 16))
        end

        @win_tile_cache.pixel_color_index(win_x % 8, win_y % 8)
      end
    end
  end
end
