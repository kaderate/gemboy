require 'ruby2d'
require 'debug'

# GameBoy DMG-01 Screen Emulator using Ruby2D
class Screen
  WINDOW_WIDTH = 160
  WINDOW_HEIGHT = 144
  BORDER = 30
  INNER_BORDER = 5
  PIXEL_SCALE = 2

  attr_reader :canvas, :title

  def initialize(logger: nil)
    @logger = logger
    @title = "Game Boy Emulator"

    width, height = compute_size
    @canvas = Ruby2D::Canvas.new(width:, height:, x: BORDER, y: BORDER, z: 1, update: false)
    puts "Initialized canvas at (#{canvas.x}, #{canvas.y}) with size #{canvas.width}x#{canvas.height}"
  end

  def initialize_window
    width, height = compute_size(with_borders: true)
    Ruby2D::Window.set(width:, height:, title:)

    add_borders
  end

  def render_framebuffer(framebuffer)
    canvas.clear
    display_framebuffer(framebuffer)
    canvas.update
  end

  private

  def compute_size(with_borders: false)
    width = WINDOW_WIDTH * PIXEL_SCALE
    height = WINDOW_HEIGHT * PIXEL_SCALE
    if with_borders
      width += BORDER * 2
      height += BORDER * 2
    end
    [width, height]
  end

  def add_borders
    # Background
    total_width, total_height = compute_size(with_borders: true)
    puts "Total size with borders: #{total_width}x#{total_height}"
    bg_color = '#000000'
    Ruby2D::Rectangle.new(x: 0, y: 0, width: total_width, height: total_height, color: bg_color)

    # Border
    x_border = y_border = BORDER - INNER_BORDER
    border_width = total_width - BORDER * 2 + INNER_BORDER * 2
    border_height = total_height - BORDER * 2 + INNER_BORDER * 2

    puts "Border position: (#{x_border}, #{y_border}), size: #{border_width}x#{border_height}"
    border_color = '#aa0000'
    Ruby2D::Rectangle.new(x: x_border, y: y_border, width: border_width, height: border_height, color: border_color)
  end

  def display_framebuffer(framebuffer)
    framebuffer.pixels.each_with_index do |line, y|
      y *= PIXEL_SCALE
      line.each_with_index do |color, x|
        x *= PIXEL_SCALE
        canvas.fill_rectangle(x:, y:, width: PIXEL_SCALE, height: PIXEL_SCALE, color:)
      end
    end
  end

  def logd(message)
    @logger&.warn message
  end

  def logi(message)
    @logger&.info message
  end
end
