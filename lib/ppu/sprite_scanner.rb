# frozen_string_literal: true

require_relative 'constants'

class PPU
  # Selects the (up to 10) OAM sprites visible on the current scanline and caches their
  # per-pixel color/priority, ready for #draw_current_dot to read one column at a time.
  class SpriteScanner
    MAX_SPRITES_PER_SCANLINE = 10

    attr_reader :sprite_pixel_cache

    def initialize(mmu:, ppu:)
      @mmu = mmu
      @ppu = ppu
      @sprite_cache = {}
      @sprite_pixel_cache = Array.new(WINDOW_WIDTH)
    end

    def clear_cache
      @sprite_cache.clear
    end

    def scan_and_cache(scanline:, obj_display_enable:)
      scanline.oam_sprites = []
      sprite_pixel_cache.fill(nil)

      return unless obj_display_enable

      select_sprites(scanline)
      cache_sprite_pixels(scanline)
    end

    private

    def select_sprites(scanline)
      sprite_size = scanline.obj_size ? 16 : 8

      # Select eligibles sprites by checking if they are on the current scanline.
      # Priority is defined by the address of the OAM memory location.
      selected_sprites_count = 0
      @ppu.read_oams.each_slice(4).with_index do |oam_memory, oam_index|
        y = oam_memory[0]
        y_screen = y - 16
        next unless y_screen <= scanline.value && scanline.value < y_screen + sprite_size

        scanline.oam_sprites << { oam_memory:, x: oam_memory[1] - 8, oam_index: }
        selected_sprites_count += 1

        break if selected_sprites_count >= MAX_SPRITES_PER_SCANLINE
      end
    end

    def cache_sprite_pixels(scanline)
      screen_y = scanline.value
      sprite_size = scanline.obj_size ? 16 : 8
      tile_data_size = sprite_size * 2 # 16 ou 32

      scanline.oam_sprites.sort_by { [_1[:x], _1[:oam_index]] }.each do |oam_sprite|
        oam_memory = oam_sprite[:oam_memory]
        base_x = oam_sprite[:x]
        base_y = oam_memory[0] - 16
        x_flipped = oam_memory[3] & 0x20 != 0
        y_flipped = oam_memory[3] & 0x40 != 0
        priority = oam_memory[3] & 0x80 == 0 ? 0 : 1
        obp_index = oam_memory[3] & 0x10 == 0 ? 0 : 1

        sprite_y = screen_y - base_y
        sprite_y = sprite_size - 1 - sprite_y if y_flipped

        tile_index = scanline.obj_size ? oam_memory[2] & 0xFE : oam_memory[2]
        tile_addr = scanline.sprite_addr(tile_index)
        tile = @sprite_cache[[tile_addr, tile_data_size]] ||= Tile.new(data: @ppu.read_vram(tile_addr, tile_data_size))

        SPRITE_WIDTH.times do |dx|
          screen_x = base_x + dx
          next if screen_x < 0 || screen_x >= WINDOW_WIDTH
          next if sprite_pixel_cache[screen_x]

          tile_x = x_flipped ? 7 - dx : dx
          color_index = tile.pixel_color_index(tile_x, sprite_y)
          next if color_index == 0

          sprite_pixel_cache[screen_x] = [color_index, priority, obp_index]
        end
      end
    end
  end
end
