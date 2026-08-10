require 'debug'
require_relative 'sdl_loader'
require_relative 'utils/fps_counter'
require_relative 'input_managers/sdl2'

def pack_color(r, g, b, a)
  (a << 24) | (b << 16) | (g << 8) | r
end

# GameBoy DMG-01 Screen Emulator using SDL
class Screen
  include InputManagers::SDL2

  WINDOW_WIDTH = 160
  WINDOW_HEIGHT = 144
  BORDER = 30
  TOTAL_WIDTH = WINDOW_WIDTH + (2 * BORDER)
  TOTAL_HEIGHT = WINDOW_HEIGHT + (2 * BORDER)
  PIXEL_SCALE = 2

  FONT_PATH = File.expand_path('../assets/fonts/InterVariable.ttf', __dir__)
  FONT_SIZE = 16
  TARGET_GB_FPS = 59.7

  BG_COLOR_SDL = pack_color(0xFF, 0xFF, 0xFF, 0xFF).freeze
  COLOR_RGBA = [
    [0x9A, 0x9E, 0x3F, 0xFF],
    [0x49, 0x6B, 0x22, 0xFF],
    [0x0E, 0x45, 0x0B, 0xFF],
    [0x1B, 0x2A, 0x09, 0xFF]
  ].freeze
  # RGBA8888 on little-endian: SDL reads bytes [A,B,G,R] from memory as 0xRRGGBBAA
  COLOR_RGBA_SDL = COLOR_RGBA.map { |r, g, b, a| pack_color(r, g, b, a) }.freeze

  attr_reader :render_queue, :fps_queue, :key_state, :audio_sampler, :logger

  def initialize(render_queue:, fps_queue:, key_state:, audio_sampler: nil, logger: nil)
    @logger = logger
    @render_queue = render_queue
    @fps_queue = fps_queue
    @key_state = key_state
    @audio_sampler = audio_sampler

    @fps_counter = FPSCounter.new
    @tick = 0
    @overlays = {}
    @overlay_texts = {}
    @blob = # AABBGGRR
      Array.new(WINDOW_WIDTH * WINDOW_HEIGHT * 4) do
        (0xFF << 24) | (0xFE << 16) | (0x80 << 8) | 0x80
      end.pack('N*')
  end

  def show
    SDL.Init(SDL::INIT_VIDEO | SDL::INIT_AUDIO | SDL::INIT_EVENTS)

    create_window_and_renderer
    create_screen_texture
    create_bg_texture
    create_stats_font

    start_display_thread
  end

  def create_window_and_renderer
    window_pos    = SDL::WINDOWPOS_CENTERED_MASK
    window_width  = (WINDOW_WIDTH * PIXEL_SCALE) + (2 * BORDER)
    window_height = (WINDOW_HEIGHT * PIXEL_SCALE) + (2 * BORDER)
    logger&.info { "Creating window #{window_width}x#{window_height}" }

    @window = SDL.CreateWindow('Gemboy', window_pos, window_pos, window_width, window_height, SDL::WINDOW_SHOWN)
    raise "SDL_CreateWindow failed: #{SDL.GetError}" if @window.null?

    @renderer = SDL.CreateRenderer(@window, -1, SDL::RENDERER_ACCELERATED | SDL::RENDERER_PRESENTVSYNC)
    raise "SDL_CreateRenderer failed: #{SDL.GetError}" if @renderer.null?
  end

  def create_screen_texture
    @screen_texture = SDL.CreateTexture(@renderer, SDL::PIXELFORMAT_RGBA8888, SDL::TEXTUREACCESS_STREAMING,
                                        WINDOW_WIDTH, WINDOW_HEIGHT)
    raise "SDL_CreateTexture (screen) failed: #{SDL.GetError}" if @screen_texture.null?

    @screen_texture_dest_rect = SDL::Rect.new.tap do |r|
      r[:x] = BORDER
      r[:y] = BORDER
      r[:w] = WINDOW_WIDTH * PIXEL_SCALE
      r[:h] = WINDOW_HEIGHT * PIXEL_SCALE
    end
  end

  def create_bg_texture
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
  end

  def create_stats_font
    SDL.TTF_Init
    @stats_font = SDL.TTF_OpenFont(FONT_PATH, FONT_SIZE)
    raise "TTF_OpenFont failed: #{SDL.GetError}" if @stats_font.null?

    # Texte sombre : le fond de la bordure (bg_color, plus haut) est blanc
    @stats_text_color = SDL::Color.new
    @stats_text_color[:r] = 0x00
    @stats_text_color[:g] = 0x00
    @stats_text_color[:b] = 0x00
    @stats_text_color[:a] = 0xFF
  end

  def start_display_thread
    event = FFI::MemoryPointer.new(:uint8, 56)

    loop do
      while SDL.PollEvent(event) == 1
        key_pressed(event) if [SDL::KEYDOWN, SDL::KEYUP].include?(event.read_uint)
      end
      draw

      Thread.pass
    end
  end

  def draw
    @tick += 1
    draw_stats
    draw_frame
    render
  end

  def draw_stats
    SDL.UpdateTexture(@bg_texture, nil, @bg_blob, TOTAL_WIDTH * 4)

    unless fps_queue.empty?
      gb_fps = fps_queue.pop until fps_queue.empty?
      @last_speed_ratio = gb_fps / TARGET_GB_FPS
    end
    speed_ratio = @last_speed_ratio || 0.0

    update_overlay(:top, format('Emu speed: %<speed>.2fx  Display FPS: %<fps>d',
                                speed: speed_ratio, fps: @fps_counter.last_fps))
    update_overlay(:bottom, format('Audio buf: %<audio>d ms', audio: buffered_audio_ms))
  end

  # Arrondi à 10 ms : sans ça la valeur bouge à chaque frame et fait regénérer
  # la texture TTF en continu (cf. la garde sur @overlay_texts).
  def buffered_audio_ms
    return 0 unless audio_sampler

    (audio_sampler.buffered_ms / 10).round * 10
  end

  def update_overlay(slot, text)
    return if @overlay_texts[slot] == text

    @overlay_texts[slot] = text

    surface_ptr = SDL.TTF_RenderText_Solid(@stats_font, text, @stats_text_color)
    return if surface_ptr.null?

    surface = SDL::Surface.new(surface_ptr)
    previous = @overlays[slot]
    SDL.DestroyTexture(previous[:texture]) if previous

    @overlays[slot] = {
      texture: SDL.CreateTextureFromSurface(@renderer, surface_ptr),
      rect: overlay_rect(slot, surface[:w], surface[:h])
    }

    SDL.FreeSurface(surface_ptr)
  end

  def overlay_rect(slot, width, height)
    margin_offset = (BORDER - height) / 2

    SDL::Rect.new.tap do |r|
      r[:x] = BORDER + 4
      r[:y] = slot == :top ? margin_offset : BORDER + (WINDOW_HEIGHT * PIXEL_SCALE) + margin_offset
      r[:w] = width
      r[:h] = height
    end
  end

  def draw_frame
    unless render_queue.empty?
      pixels_frame = render_queue.pop until render_queue.empty?
      @blob = pixels_frame.map { |color| COLOR_RGBA_SDL.fetch(color) }.pack('N*')
    end

    SDL.UpdateTexture(@screen_texture, nil, @blob, WINDOW_WIDTH * 4) # * 4 = RGBA8888
  end

  # Blocking SDL functions means they will release the GVL during execution
  # It's required to use SDL::RenderPresent in a blocking manner to avoid keeping the GVL locked
  # for too long (frame duration)
  module SDLBlocking
    extend FFI::Library

    ffi_lib SDL.ffi_libraries.map(&:name) # réutilise la lib déjà chargée par le gem
    attach_function :RenderPresent, :SDL_RenderPresent, [:pointer], :void, blocking: true
  end

  def render
    SDL.RenderClear(@renderer)

    # Order matters: background first, then screen, then stats overlay on top
    SDL.RenderCopy(@renderer, @bg_texture, nil, @bg_texture_dest_rect)
    SDL.RenderCopy(@renderer, @screen_texture, nil, @screen_texture_dest_rect)
    @overlays.each_value { |overlay| SDL.RenderCopy(@renderer, overlay[:texture], nil, overlay[:rect]) }

    SDLBlocking.RenderPresent(@renderer) # Throttled by SDL::RENDERER_PRESENTVSYNC (~60fps)
    @fps_counter.update
  end
end
