require 'ruby2d'

# GameBoy DMG-01 PPU Emulator en Ruby
class PPU
  attr_accessor :cpu, :title, :cycles, :canvas

  WINDOW_WIDTH = 160
  WINDOW_HEIGHT = 144
  PIXEL_SCALE = 2

  def initialize(cpu)
    @cpu = cpu
    @title = "Game Boy Emulator"
    @cycles = 0
    @canvas = Ruby2D::Canvas.new(
      width: WINDOW_WIDTH * PIXEL_SCALE,
      height: WINDOW_HEIGHT * PIXEL_SCALE,
      update: false
    )
  end

  def initialize_window
    width = WINDOW_WIDTH * PIXEL_SCALE
    height = WINDOW_HEIGHT * PIXEL_SCALE
    Ruby2D::Window.set width:, height:, title:
  end

  def tick(nb_cycles)
    self.cycles += nb_cycles
    if cycles >= 456
      self.cycles -= 456
      puts "*** [PPU] Rendering screen... (#{cycles} cycles remaining)"
      render
    end
    puts " *** [PPU] tick: #{cycles} cycles (#{nb_cycles} cycles added)"
  end

  def render
    if lcd_control[:lcd_enable]
      puts "*** [PPU] LCD is enabled, rendering screen"
      render_screen
    else
      puts "*** [PPU] LCD is disabled, clearing screen"
      canvas.clear
    end
  end

  def render_screen
    canvas.clear
    display_background
    # TODO: Afficher les sprites
    # TODO: Afficher la fenêtre (window)
    # TODO: Gérer le scrolling (SCX, SCY) pour ajuster la position de la caméra
    canvas.update
  end

  def display_background
    tiles = read_background_tiles
    display_tiles(tiles)
  end
  
  def read_tile_data(tile_index)
    base_address = lcd_control[:bg_and_window_tile_data_select] ? 0x8000 : 0x8800
    cpu.read_vram(base_address + tile_index * 16, 16) # 16 bytes per tile
  end

  def read_background_tiles
    tiles = []
    base_address = lcd_control[:bg_tile_map_display_select] ? 0x9C00 : 0x9800
    (0...32).each do |y|
      (0...32).each do |x|
        tile_index = cpu.read_vram(base_address + y * 32 + x)
        tile_data = read_tile_data(tile_index)
        tiles << Tile.new(data: tile_data, x:, y:)
      end
    end
    tiles
  end

  def display_tiles(tiles)
    tiles.each do |tile|
      TileDisplayer.new(tile, canvas).display
    end
  end

  class Tile
    attr_reader :lines, :x, :y

    def initialize(data:, x:, y:)
      @x = x
      @y = y

      @lines = initialize_lines(data)
    end

    def initialize_lines(data)
      res = []
      data.each_slice(2) do |byte1, byte2|
        # Decoder les 2 bytes pour obtenir les couleurs des 8 pixels de la ligne
        res << BPPDecoder.new(byte1, byte2)
      end
      res
    end

    def pixel_color(x, y)
      lines[y][x]
    end
  end

  def lcd_control = cpu.lcd_control

  class TileDisplayer
    attr_reader :tile, :canvas

    def initialize(tile, canvas)
      @tile = tile
      @canvas = canvas
    end

    def display
      (0...8).each do |pixel_y|
        (0...8).each do |pixel_x|
          base_color = tile.pixel_color(pixel_x, pixel_y)
          x = tile.x * 8 + pixel_x
          y = tile.y * 8 + pixel_y

          display_pixel(x, y, base_color)
        end
      end
    end

    def display_pixel(x, y, base_color)
      color = self.class.hex_color_from_value(base_color)
      canvas.fill_rectangle(
        x: x * PIXEL_SCALE,
        y: y * PIXEL_SCALE,
        width: PIXEL_SCALE,
        height: PIXEL_SCALE,
        color:
      )
    end

    def self.hex_color_from_value(value)
      r = (value * 16) % 256
      g = (value * 16) % 256
      b = (value * 16) % 256
      format("#%02x%02x%02x", r, g, b)
    end
  end

  class BPPDecoder
    attr_reader :pixels

    def initialize(byte1, byte2, palette = [0xFF, 0xAA, 0x55, 0x00])
      @pixels = []
      (0...8).each do |x|
        bit1 = (byte1 >> (7 - x)) & 0x01
        bit2 = (byte2 >> (7 - x)) & 0x01
        color_value = (bit2 << 1) | bit1
        @pixels << palette[color_value]
      end
    end

    def [](x)
      pixels[x]
    end
  end
end
