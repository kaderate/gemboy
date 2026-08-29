# frozen_string_literal: true

class PPU
  LcdControl = Struct.new(:bytes) do
    def window_tile_map_display_select = bytes.anybits?(0x40)
    def window_display_enable = bytes.anybits?(0x20)
    def bg_and_window_tile_data_select = bytes.anybits?(0x10)
    def bg_tile_map_display_select = bytes.anybits?(0x08)
    def obj_size = bytes.anybits?(0x04)
    def obj_display_enable = bytes.anybits?(0x02)
    def bg_display = bytes.anybits?(0x01)
    def lcd_enable = bytes.anybits?(0x80)
  end
end
