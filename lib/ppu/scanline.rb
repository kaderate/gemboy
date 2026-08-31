# frozen_string_literal: true

require_relative '../ppu'

class PPU
  class Scanline
    TILE_DATA_ADDRS = [0x8000, 0x9000].freeze
    TILE_MAP_ADDRS = [0x9800, 0x9C00].freeze
    TOTAL_SCANLINES = 154
    PRECOMPUTED_PALETTE = Array.new(256) { |b| [0, 1, 2, 3].map { |i| (b >> (i * 2)) & 0x03 }.freeze }.freeze

    attr_accessor :value, :scx, :scy, :oam_sprites, :ppu, :bg_tile_map_addr, :tile_data_addr, :sprite_data_addr,
                  :lcd_enabled, :obj_size, :wx, :wy, :window_enabled, :window_tile_map_addr, :bg_palette,
                  :obj_palette0, :obj_palette1, :bg_enabled

    def initialize(ppu:)
      @value = 0
      @scx = 0
      @scy = 0
      @oam_sprites = []

      @ppu = ppu
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

      snapshot_for_render = ppu.snapshot_for_render
      self.scx = snapshot_for_render[:scx]
      self.scy = snapshot_for_render[:scy]
      self.wx  = snapshot_for_render[:wx]
      self.wy  = snapshot_for_render[:wy]
      self.bg_palette   = PRECOMPUTED_PALETTE[snapshot_for_render[:bgp]]
      self.obj_palette0 = PRECOMPUTED_PALETTE[snapshot_for_render[:obp0]]
      self.obj_palette1 = PRECOMPUTED_PALETTE[snapshot_for_render[:obp1]]

      lcdc = ppu.lcd_control
      self.bg_tile_map_addr     = lcdc.bg_tile_map_display_select ? TILE_MAP_ADDRS[1] : TILE_MAP_ADDRS[0]
      self.tile_data_addr       = lcdc.bg_and_window_tile_data_select ? TILE_DATA_ADDRS[0] : TILE_DATA_ADDRS[1]
      self.obj_size             = lcdc.obj_size
      self.lcd_enabled          = lcdc.lcd_enable
      self.bg_enabled           = lcdc.bg_display
      self.window_enabled       = lcdc.window_display_enable
      self.window_tile_map_addr = lcdc.window_tile_map_display_select ? TILE_MAP_ADDRS[1] : TILE_MAP_ADDRS[0]
    end

    def tile_addr(tile_index)
      return tile_data_addr + (tile_index * 16) if tile_data_addr == TILE_DATA_ADDRS[0]

      tile_data_addr + ((tile_index < 128 ? tile_index : tile_index - 256) * 16)
    end

    def sprite_addr(tile_index) = sprite_data_addr + (tile_index * 16)

    def reset_ly!
      @value = 0
    end
  end
end
