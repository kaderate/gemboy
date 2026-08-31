# frozen_string_literal: true

require_relative 'constants'
require_relative 'coordinate'

class PPU
  # Selects the (up to 10) OAM sprites visible on the current scanline and caches their
  # per-pixel color/priority, ready for #draw_current_dot to read one column at a time.
  class SpriteScanner
    MAX_SPRITES_PER_SCANLINE = 10

    class DMGPaletteFetcher
      def self.fetch(oam_memory)
        palette = oam_memory[3] & 0x10 == 0 ? 0 : 1 # OBP1 or OBP0
        [palette, 0]
      end
    end

    class CGBPaletteFetcher
      def self.fetch(oam_memory)
        palette = oam_memory[3] & 0x7
        bank = (oam_memory[3] >> 3) & 0x1
        [palette, bank]
      end
    end

    attr_reader :sprite_pixel_cache

    def initialize(mmu:, vram:, oam_reader:)
      @mmu = mmu
      @vram = vram
      @oam_reader = oam_reader
      @sprite_cache = {}
      @sprite_pixel_cache = Array.new(WINDOW_WIDTH)
      @palette_fetcher = mmu.model.cgb? ? CGBPaletteFetcher : DMGPaletteFetcher
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
      @oam_reader.read_oams.each_slice(4).with_index do |oam_memory, oam_index|
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
        palette, bank = @palette_fetcher.fetch(oam_memory)

        sprite_y = Coordinate.flip(screen_y - base_y, y_flipped, sprite_size)

        tile_index = scanline.obj_size ? oam_memory[2] & 0xFE : oam_memory[2]
        tile_addr = scanline.sprite_addr(tile_index)
        cache_key = [bank, tile_addr, tile_data_size]
        tile = @sprite_cache[cache_key] ||= Tile.new(data: @vram.read(tile_addr, tile_data_size, bank:))

        SPRITE_WIDTH.times do |dx|
          screen_x = base_x + dx
          next if screen_x < 0 || screen_x >= WINDOW_WIDTH
          next if sprite_pixel_cache[screen_x]

          tile_x = Coordinate.flip(dx, x_flipped)
          color_index = tile.pixel_color_index(tile_x, sprite_y)
          next if color_index == 0

          sprite_pixel_cache[screen_x] = [color_index, priority, palette]
        end
      end
    end
  end
end
