# frozen_string_literal: true

require_relative '../ppu'

class PPU
  class Scanline
    TILE_DATA_ADDRS = [0x8000, 0x9000].freeze
    TOTAL_SCANLINES = 154

    attr_accessor :value, :scx, :scy, :oam_sprites, :mmu, :bg_tile_map_addr, :tile_data_addr, :sprite_data_addr,
                  :lcd_enabled, :obj_size, :wx, :wy, :window_enabled, :window_tile_map_addr, :bg_palette,
                  :obj_palette0, :obj_palette1, :bg_enabled

    def initialize(mmu:)
      @value = 0
      @scx = 0
      @scy = 0
      @oam_sprites = []

      @mmu = mmu
    end

    def tick!
      @value = (@value + 1) % TOTAL_SCANLINES
    end

    # dmg-acid2 (et des jeux réels) écrivent des registres depuis une interruption LYC servie
    # pendant le mode_2 (OAM scan) d'une ligne, en s'attendant à ce que l'effet soit visible dès le
    # mode_3 (affichage) de CETTE MÊME ligne -- y compris pour le scan OAM lui-même (obj_display_enable
    # activé en plein mode_2 doit quand même faire apparaître le sprite sur cette ligne). On lit donc
    # tous les registres (sprite scan + BG/window/palette) au début du mode_3, une fois le mode_2
    # entièrement écoulé, plutôt que de les figer au début du mode_2 -- ce qui appliquerait ces
    # changements une ligne trop tard.
    def mode_updated!(new_mode)
      return unless new_mode == :mode_3

      self.sprite_data_addr = 0x8000

      self.scx = mmu.read_scroll_x
      self.scy = mmu.read_scroll_y

      lcdc = mmu.lcd_control
      self.bg_tile_map_addr = lcdc.bg_tile_map_display_select ? 0x9C00 : 0x9800
      self.tile_data_addr   = lcdc.bg_and_window_tile_data_select ? 0x8000 : 0x9000
      self.obj_size = lcdc.obj_size
      self.lcd_enabled = lcdc.lcd_enable
      self.bg_enabled = lcdc.bg_display

      self.wx = mmu.read_window_x
      self.wy = mmu.read_window_y
      self.window_enabled = lcdc.window_display_enable
      self.window_tile_map_addr = lcdc.window_tile_map_display_select ? 0x9C00 : 0x9800

      self.bg_palette = mmu.read_bg_palette
      self.obj_palette0 = mmu.read_obj_palette0
      self.obj_palette1 = mmu.read_obj_palette1
    end

    def tile_addr(tile_index)
      return tile_data_addr + (tile_index * 16) if tile_data_addr == 0x8000

      tile_data_addr + ((tile_index < 128 ? tile_index : tile_index - 256) * 16)
    end

    def sprite_addr(tile_index)
      sprite_data_addr + (tile_index * 16)
    end
  end
end
