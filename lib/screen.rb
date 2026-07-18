require 'debug'
require 'sdl2'
require_relative 'utils/fps_counter'
require_relative 'input_managers/sdl2'

SDL_LIB_PREFIX = `pkg-config --variable=libdir sdl2 2>/dev/null`.strip
SDL_LIB = SDL_LIB_PREFIX.empty? ? nil : "#{SDL_LIB_PREFIX}/libSDL2-2.0.0.dylib"
raise 'SDL2 not found (brew install sdl2)' unless SDL_LIB && File.exist?(SDL_LIB)

SDL.load_lib(SDL_LIB)

def pack_color(r, g, b, a)
  (a << 24) | (b << 16) | (g << 8) | r
end

# GameBoy DMG-01 Screen Emulator using SDL
class Screen
  include InputManagers::SDL2

  WINDOW_WIDTH = 160
  WINDOW_HEIGHT = 144
  BORDER = 30
  TOTAL_WIDTH = WINDOW_WIDTH + 2 * BORDER
  TOTAL_HEIGHT = WINDOW_HEIGHT + 2 * BORDER
  PIXEL_SCALE = 2

  BG_COLOR_SDL = pack_color(0xFF, 0xFF, 0xFF, 0xFF).freeze
  COLOR_RGBA = [
    [0x9A, 0x9E, 0x3F, 0xFF],
    [0x49, 0x6B, 0x22, 0xFF],
    [0x0E, 0x45, 0x0B, 0xFF],
    [0x1B, 0x2A, 0x09, 0xFF]
  ].freeze
  # RGBA8888 on little-endian: SDL reads bytes [A,B,G,R] from memory as 0xRRGGBBAA
  COLOR_RGBA_SDL = COLOR_RGBA.map { |r, g, b, a| pack_color(r, g, b, a) }.freeze

  attr_reader :render_queue, :fps_queue, :key_state, :logger

  def initialize(render_queue:, fps_queue:, key_state:, logger: nil)
    @logger = logger
    @render_queue = render_queue
    @fps_queue = fps_queue
    @key_state = key_state

    @fps_counter = FPSCounter.new
    @tick = 0
    @blob = # AABBGGRR
      Array.new(WINDOW_WIDTH * WINDOW_HEIGHT * 4) do
        (0xFF << 24) | (0xFE << 16) | (0x80 << 8) | 0x80
      end.pack('N*')
  end

  def show # same naming convention as Gosu::Window#show to simplify the main loop
    SDL.Init(SDL::INIT_VIDEO | SDL::INIT_AUDIO | SDL::INIT_EVENTS)

    window_pos    = SDL::WINDOWPOS_CENTERED_MASK
    window_width  = WINDOW_WIDTH * PIXEL_SCALE + 2 * BORDER
    window_height = WINDOW_HEIGHT * PIXEL_SCALE + 2 * BORDER
    puts "Creating window #{window_width}x#{window_height}"

    @window = SDL.CreateWindow('Gemboy', window_pos, window_pos, window_width, window_height, SDL::WINDOW_SHOWN)
    raise "SDL_CreateWindow failed: #{SDL.GetError}" if @window.null?

    @renderer = SDL.CreateRenderer(@window, -1, SDL::RENDERER_ACCELERATED | SDL::RENDERER_PRESENTVSYNC)
    raise "SDL_CreateRenderer failed: #{SDL.GetError}" if @renderer.null?

    @screen_texture = SDL.CreateTexture(@renderer, SDL::PIXELFORMAT_RGBA8888, SDL::TEXTUREACCESS_STREAMING,
                                        WINDOW_WIDTH, WINDOW_HEIGHT)
    raise "SDL_CreateTexture (screen) failed: #{SDL.GetError}" if @screen_texture.null?

    @screen_texture_dest_rect = SDL::Rect.new.tap do |r|
      r[:x] = BORDER
      r[:y] = BORDER
      r[:w] = WINDOW_WIDTH * PIXEL_SCALE
      r[:h] = WINDOW_HEIGHT * PIXEL_SCALE
    end

    @bg_texture = SDL.CreateTexture(@renderer, SDL::PIXELFORMAT_RGBA8888, SDL::TEXTUREACCESS_STREAMING, TOTAL_WIDTH,
                                    TOTAL_HEIGHT)
    raise "SDL_CreateTexture (bg) failed: #{SDL.GetError}" if @bg_texture.null?

    @bg_texture_dest_rect = SDL::Rect.new.tap do |r|
      r[:x] = 0
      r[:y] = 0
      r[:w] = TOTAL_WIDTH * PIXEL_SCALE
      r[:h] = TOTAL_HEIGHT * PIXEL_SCALE
    end

    bg_color = (0x0 << 24) | (0xFF << 16) | (0xFF << 8) | 0xFF
    @bg_blob = Array.new(TOTAL_WIDTH * TOTAL_HEIGHT * 4) { bg_color }.pack('N*')

    start_display_thread
  end

  def start_display_thread
    puts 'Starting display'
    event = FFI::MemoryPointer.new(:uint8, 56)

    loop do
      while SDL.PollEvent(event) == 1
        key_pressed(event) if [SDL::KEYDOWN, SDL::KEYUP].include?(event.read_uint)
      end
      draw
      sleep 0.0001
    end
  end

  def draw
    @tick += 1
    draw_fps
    draw_frame
    render
  end

  def draw_fps
    SDL.UpdateTexture(@bg_texture, nil, @bg_blob, TOTAL_WIDTH * 4)

    # TODO
  end

  def draw_frame
    unless render_queue.empty?
      pixels_frame = render_queue.pop
      @blob = pixels_frame.map { |color| COLOR_RGBA_SDL.fetch(color) }.pack('N*')
    end

    SDL.UpdateTexture(@screen_texture, nil, @blob, WINDOW_WIDTH * 4) # * 4 = RGBA8888
  end

  def render
    SDL.RenderClear(@renderer)

    # Order matters: background first, then screen
    SDL.RenderCopy(@renderer, @bg_texture, nil, @bg_texture_dest_rect)
    SDL.RenderCopy(@renderer, @screen_texture, nil, @screen_texture_dest_rect)

    SDL.RenderPresent(@renderer) # Throttled by SDL::RENDERER_PRESENTVSYNC (~60fps)
  end
end
