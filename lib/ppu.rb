require 'ruby2d'

# GameBoy DMG-01 PPU Emulator en Ruby
class PPU
  attr_accessor :cpu, :title

  WINDOW_WIDTH = 160
  WINDOW_HEIGHT = 144
  PIXEL_SCALE = 2

  delegate :lcd_control, to: :cpu

  def initialize(cpu)
    @cpu = cpu
    @title = "Game Boy Emulator"
  end

  def initialize_window
    width = WINDOW_WIDTH * PIXEL_SCALE
    height = WINDOW_HEIGHT * PIXEL_SCALE
    Ruby2D::Window.set width:, height:, title:
  end

  def render
    if lcd_control[:lcd_enable]
      render_screen
    else
      Ruby2D::Window.clear
    end
  end

  def render_screen
    display_background
    # TODO: Afficher les sprites
    # TODO: Afficher la fenêtre (window)
    set_viewport
  end

  def set_viewport
    # TODO: Gérer le scrolling (SCX, SCY) pour ajuster la position de la caméra
  end

  def display_background
    tiles = read_background_tiles

    display_tiles(tiles)
  end

  def display_tiles(tiles)
    Ruby2D::Window.clear
    tiles.each do |tile|
      display_tile(tile)
    end
  end

  def read_background_tiles
    tiles = []
    base_address = lcd_control[:bg_tile_map_display_select] ? 0x9C00 : 0x9800
    (0...32).each do |y|
      (0...32).each do |x|
        tile_index = cpu.read_vram(base_address + y * 32 + x)
        tile_data = read_tile_data(tile_index)
        tiles << Tile.new(tile_data)
      end
    end
    tiles
  end
  
  def read_tile_data(tile_index)
    base_address = lcd_control[:bg_and_window_tile_data_select] ? 0x8000 : 0x8800
    cpu.read_vram(base_address + tile_index * 16, 16) # 16 bytes per tile
  end

  def render_screen_old
    color = hex_color_from_value(cpu.a)
    size = WINDOW_WIDTH * PIXEL_SCALE
    Ruby2D::Window.clear
    Ruby2D::Square.new(x: 0, y: 0, size:, color:)
  end

  class Tile
    attr_reader :lines

    def initialize(data)
      data.each_slice(2) do |byte1, byte2|
        @lines ||= []
        @lines << 2BPP.new(byte1, byte2)
      end
    end

    def pixel_color_hex(x, y)
      byte1 = @data[y * 2]
      byte2 = @data[y * 2 + 1]
      2BPP.new(byte1, byte2).pixel_color_hex
    end
  end

  class TileDisplayer
    attr_reader :tile

    def initialize(tile)
      @tile = tile
    end

    def display
      (0...8).each do |y|
        (0...8).each do |x|
          color = tile.pixel_color_hex(x, y)
          Ruby2D::Square.new(x: x * PIXEL_SCALE, y: y * PIXEL_SCALE, size: PIXEL_SCALE, color:)
        end
      end
    end
  end


  class 2BPP
    attr_reader :byte1, :byte2

    def initialize(byte1, byte2, palette = [0x00, 0x55, 0xAA, 0xFF])
      @byte1 = byte1
      @byte2 = byte2
    end

    def pixel_color
      bit1 = (byte1 >> (7 - x)) & 0x01
      bit2 = (byte2 >> (7 - x)) & 0x01

      (bit2 << 1) | bit1
    end

    def pixel_color_hex
      value = pixel_color
      self.class.hex_color_from_value(value)
    end

    def self.hex_color_from_value(value)
      r = (value * 16) % 256
      g = (value * 16) % 256
      b = (value * 16) % 256
      format("#%02x%02x%02x", r, g, b)
    end
  end
end
