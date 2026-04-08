require 'ruby2d'

# GameBoy DMG-01 PPU Emulator en Ruby
class PPU
  attr_accessor :mmu, :title, :cycles, :canvas

  WINDOW_WIDTH = 160
  WINDOW_HEIGHT = 144
  BORDER = 30
  INNER_BORDER = 5
  PIXEL_SCALE = 2

  def initialize(mmu, logger: nil)
    @logger = logger
    @mmu = mmu
    @title = "Game Boy Emulator"
    @cycles = 0
    @canvas = Ruby2D::Canvas.new(
      width: WINDOW_WIDTH * PIXEL_SCALE,
      height: WINDOW_HEIGHT * PIXEL_SCALE,
      x: BORDER,
      y: BORDER,
      z: 1,
      update: false
    )
  end

  def initialize_window
    width = WINDOW_WIDTH * PIXEL_SCALE + BORDER * 2
    height = WINDOW_HEIGHT * PIXEL_SCALE + BORDER * 2
    Ruby2D::Window.set width:, height:, title:
  end

  def tick(nb_cycles)
    self.cycles += nb_cycles
    logi " *** [PPU] tick: #{cycles} cycles (#{nb_cycles} cycles added)"

    if renderable?
      logi " *** [PPU] Ready to render! (#{cycles} cycles)"
      reset_cycles
      return true
    else
      return false
    end
  end

  def render
    logd "*** [PPU] Rendering screen... (#{cycles} cycles remaining)"
    if lcd_control[:lcd_enable]
      logd "*** [PPU] LCD is enabled, rendering screen"
      render_screen
    else
      logd "*** [PPU] LCD is disabled, clearing screen"
      canvas.clear
    end
  end

  private

  def reset_cycles
    self.cycles -= 456
  end

  def renderable?
    cycles >= 456
  end

  def render_screen
    tile_data_address = tile_data_base_address
    bg_tile_map_address = bg_tile_map_display_select
    logd "Tile data at 0x#{tile_data_address.to_s(16)}: #{@mmu.read_vram(tile_data_address, 8).map { _1.to_s(16) }.inspect}"
    logd "Tilemap at 0x#{bg_tile_map_address.to_s(16)}: #{@mmu.read_vram(bg_tile_map_address, 16).map { _1.to_s(16) }.inspect}"
    logd "LCD Control: #{lcd_control.inspect}"
    logd '-' * 50

    canvas.clear
    add_borders
    display_background
    # TODO: Afficher les sprites
    # TODO: Afficher la fenêtre (window)
    # TODO: Gérer le scrolling (SCX, SCY) pour ajuster la position de la caméra
    canvas.update
  end

  def add_borders
    # Background
    total_width = WINDOW_WIDTH * PIXEL_SCALE + BORDER * 2
    total_height = WINDOW_HEIGHT * PIXEL_SCALE + BORDER * 2
    bg_color = '#000000'
    Ruby2D::Rectangle.new(x: 0, y: 0, width: total_width, height: total_height, color: bg_color)

    # Border
    x_border = y_border = BORDER - INNER_BORDER
    border_width = total_width - BORDER * 2 + INNER_BORDER * 2
    border_height = total_height - BORDER * 2 + INNER_BORDER * 2
    border_color = '#aaaaaa'
    Ruby2D::Rectangle.new(x: x_border, y: y_border, width: border_width, height: border_height, color: border_color)
  end

  def display_background
    tiles = read_background_tiles
    display_tiles(tiles)
  end
  
  def read_tile_data(tile_index)
    mmu.read_vram(tile_data_base_address + tile_index * 16, 16) # 16 bytes per tile
  end

  def read_background_tiles
    tiles = []
    base_address = bg_tile_map_display_select
    (0...32).each do |y|
      (0...32).each do |x|
        tile_index = mmu.read_vram(base_address + y * 32 + x)
        tile_data = read_tile_data(tile_index)
        tiles << Tile.new(data: tile_data, x:, y:)
      end
    end
    tiles
  end

  def tile_data_base_address
    lcd_control[:bg_and_window_tile_data_select] ? 0x8000 : 0x8800
  end

  def bg_tile_map_display_select
    lcd_control[:bg_tile_map_display_select] ? 0x9C00 : 0x9800
  end

  def display_tiles(tiles)
    tiles.each do |tile|
      TileDisplayer.new(tile, canvas).display
    end
  end

  def logd(message)
    @logger&.warn message
  end

  def logi(message)
    @logger&.info message
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

  def lcd_control = mmu.read_lcd_control

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
    DMG_PALETTE = [0xFF, 0xAA, 0x55, 0x00] # Blanc, Gris clair, Gris foncé, Noir

    attr_reader :pixels

    def initialize(byte1, byte2, palette = DMG_PALETTE)
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
