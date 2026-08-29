# frozen_string_literal: true

class PPU
  # Window dimensions
  WINDOW_WIDTH = 160
  WINDOW_HEIGHT = 144
  BACKGROUND_WIDTH = 256
  BACKGROUND_HEIGHT = 256
  SPRITE_WIDTH = 8
  BORDER = 30
  INNER_BORDER = 5
  PIXEL_SCALE = 2

  # Scanline timing
  CYCLES_PER_SCANLINE = 456

  # Registers
  REGISTERS = {
    lcd_control: 0xFF40,
    lcd_stat: 0xFF41,
    scy: 0xFF42,
    scx: 0xFF43,
    ly: 0xFF44,
    lyc: 0xFF45,
    wy: 0xFF4A,
    wx: 0xFF4B,
    bgp: 0xFF47,
    obp0: 0xFF48,
    obp1: 0xFF49
  }.freeze
  REGISTERS_FROM_ADDR = REGISTERS.invert.freeze

  # Memory areas
  VRAM_TILE_DATA_END = 0x97FF
end
