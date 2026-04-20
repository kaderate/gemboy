require 'gosu'
require 'debug'

require_relative 'utils/fps_counter'
require_relative 'input_manager'

# GameBoy DMG-01 Screen Emulator using Gosu
class Screen < Gosu::Window
  include InputManager

  WINDOW_WIDTH = 160
  WINDOW_HEIGHT = 144
  BORDER = 30
  PIXEL_SCALE = 2

  COLOR_RGBA_PACKED = [
    [240, 240, 240, 255],
    [160, 160, 160, 255],
    [80, 80, 80, 255],
    [0, 0, 0, 255]
  ].map { _1.pack('C4').freeze }.freeze

  GOSU_COLORS = [
    Gosu::Color.argb(0xFF9A9E3F),
    Gosu::Color.argb(0xFF496B22),
    Gosu::Color.argb(0xFF0E450B),
    Gosu::Color.argb(0xFF1B2A09)
  ].freeze

  attr_reader :render_queue, :fps_queue, :key_state, :logger

  def initialize(render_queue:, fps_queue:, key_state:, logger: nil)
    @logger = logger
    @render_queue = render_queue
    @fps_queue = fps_queue
    @key_state = key_state

    @fps_counter = FPSCounter.new
    @rendering_mode = :rect_rle

    # For "image" rendering mode
    @blob = "\x00".b * (WINDOW_WIDTH * WINDOW_HEIGHT * 4)

    @font = Gosu::Font.new(16)

    super(WINDOW_WIDTH * PIXEL_SCALE + BORDER * 2, WINDOW_HEIGHT * PIXEL_SCALE + BORDER * 2, fullscreen: false, caption: "Game Boy Emulator")
  end

  def draw
    draw_fps

    case @rendering_mode
    when :image then draw_image
    when :rect then draw_rect
    when :rect_rle then draw_rect_rle
    end
  end

  def draw_fps
    @fps_counter.update
    internal_fps = @fps_queue.pop until @fps_queue.empty?

    @font.draw("GOSU FPS: #{@fps_counter.last_fps}", BORDER,  10, 0, 1.0, 1.0, 0xffffffff)
    @font.draw("Internal FPS: #{internal_fps}", 250,  10, 0, 1.0, 1.0, 0xffffffff)
  end

  def draw_image
    unless render_queue.empty?
      pixels_frame = render_queue.pop
      pixels_frame.each_with_index { |color, i| @blob[i * 4, 4] = COLOR_RGBA_PACKED.fetch(color) }
      @current_image = Gosu::Image.from_blob(WINDOW_WIDTH, WINDOW_HEIGHT, @blob)
    end
    @current_image&.draw(BORDER, BORDER, 0, PIXEL_SCALE, PIXEL_SCALE)
  end

  def draw_rect
    @pixels_frame = render_queue.pop unless render_queue.empty?
    return unless @pixels_frame

    @pixels_frame.each_with_index do |color_idx, i|
      x = (i % WINDOW_WIDTH) * PIXEL_SCALE
      y = (i / WINDOW_WIDTH) * PIXEL_SCALE
      Gosu.draw_rect(BORDER + x, BORDER + y, PIXEL_SCALE, PIXEL_SCALE, GOSU_COLORS.fetch(color_idx), 0)
    end
  end

  def draw_rect_rle
    @pixels_frame = render_queue.pop unless render_queue.empty?
    return unless @pixels_frame

    @pixels_frame.each_slice(WINDOW_WIDTH).each_with_index do |row, y|
      x_start = 0
      row.each_cons(2).each_with_index do |(c1, c2), x|
        next if c1 == c2
        Gosu.draw_rect(BORDER + x_start * PIXEL_SCALE, BORDER + y * PIXEL_SCALE,
                       (x + 1 - x_start) * PIXEL_SCALE, PIXEL_SCALE,
                       GOSU_COLORS.fetch(c1), 0)
        x_start = x + 1
      end

      # Dernier pixel
      Gosu.draw_rect(BORDER + x_start * PIXEL_SCALE, BORDER + y * PIXEL_SCALE,
                     (WINDOW_WIDTH - x_start) * PIXEL_SCALE, PIXEL_SCALE,
                     GOSU_COLORS.fetch(row.last), 0)
    end
  end
end
