require_relative 'sdl_loader'
require_relative 'utils/fps_counter'
require_relative 'input_managers/sdl2'

# GameBoy DMG-01 Screen Emulator using SDL
# It's executed in the main thread (SDL requirement)
class Screen
  include InputManagers::SDL2

  WINDOW_WIDTH = 160
  WINDOW_HEIGHT = 144
  BORDER = 30
  TOTAL_WIDTH = WINDOW_WIDTH + (2 * BORDER)
  TOTAL_HEIGHT = WINDOW_HEIGHT + (2 * BORDER)
  PIXEL_SCALE = 2
  WINDOW_PIXEL_WIDTH = (WINDOW_WIDTH * PIXEL_SCALE) + (2 * BORDER)
  WINDOW_PIXEL_HEIGHT = (WINDOW_HEIGHT * PIXEL_SCALE) + (2 * BORDER)
  FLASH_TTL = 4 * 60
  # Kept small: the top border only has ~140px left of the speed/FPS line at FONT_SIZE
  SAVE_STATE_HELP = '1-9 slot · F5/F8'.freeze

  FONT_PATH = File.expand_path('../assets/fonts/InterVariable.ttf', __dir__)
  FONT_SIZE = 16
  TARGET_GB_FPS = 59.7

  # RGBA8888 on little-endian: SDL reads bytes [A,B,G,R] from memory as 0xRRGGBBAA
  def self.pack_color(r, g, b, a) = (a << 24) | (b << 16) | (g << 8) | r

  BG_COLOR_SDL = pack_color(0xC4, 0xBE, 0xB5, 0xFF).freeze

  attr_reader :render_queue, :fps_queue, :key_state, :audio_sampler, :logger, :save_state_ui

  # rubocop:disable-next Metrics/ParameterLists
  def initialize(render_queue:, fps_queue:, key_state:, audio_sampler: nil, logger: nil, save_state_ui: nil,
                 show_overlays: true)
    @logger = logger
    @save_state_ui = save_state_ui
    @show_overlays = show_overlays
    @render_queue = render_queue
    @fps_queue = fps_queue
    @key_state = key_state
    @audio_sampler = audio_sampler

    @fps_counter = FPSCounter.new
    @tick = 0
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
    build_stats_overlays

    start_display_loop
  end

  def build_stats_overlays
    SDL.TTF_Init

    font = SDL.TTF_OpenFont(FONT_PATH, FONT_SIZE)
    raise "SDL TTF_OpenFont failed: #{SDL.GetError}" if font.null?

    text_color = SDL::Color.new.tap do |c|
      c[:r] = 0x00
      c[:g] = 0x00
      c[:b] = 0x00
      c[:a] = 0xFF
    end

    overlay_args = { renderer: @renderer, text_color:, font: }
    left = BORDER + 4
    right = WINDOW_PIXEL_WIDTH - 4
    bottom = BORDER + (WINDOW_HEIGHT * PIXEL_SCALE)

    @overlays = {
      top: Overlay.new(**overlay_args, x: left, y_origin: 0),
      bottom: Overlay.new(**overlay_args, x: left, y_origin: bottom),
      save_state: Overlay.new(**overlay_args, x: right, y_origin: bottom, align: :right, ttl: FLASH_TTL),
      save_state_help: Overlay.new(**overlay_args, x: right, y_origin: 0, align: :right, ttl: FLASH_TTL)
    }
  end

  def create_window_and_renderer
    window_pos = SDL::WINDOWPOS_CENTERED_MASK
    logger&.info { "Creating window #{WINDOW_PIXEL_WIDTH}x#{WINDOW_PIXEL_HEIGHT}" }

    @window = SDL.CreateWindow('Gemboy', window_pos, window_pos, WINDOW_PIXEL_WIDTH, WINDOW_PIXEL_HEIGHT,
                               SDL::WINDOW_SHOWN)
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

    @bg_blob = Array.new(TOTAL_WIDTH * TOTAL_HEIGHT * 4) { BG_COLOR_SDL }.pack('N*')
  end

  def start_display_loop
    event = FFI::MemoryPointer.new(:uint8, 56)

    loop do
      while SDL.PollEvent(event) == 1
        key_pressed(event) if [SDL::KEYDOWN, SDL::KEYUP].include?(event.read_uint)
        handle_quit if event.read_uint == SDL::QUIT
      end
      draw

      Thread.pass
    end
  end

  def handle_quit
    logger&.info { 'Quit requested, shutting down' }
    # Must go through exit: Engine's at_exit hook writes the .sav file
    exit(0)
  end

  def draw
    @tick += 1
    draw_stats
    draw_frame
    render
  end

  def draw_stats
    SDL.UpdateTexture(@bg_texture, nil, @bg_blob, TOTAL_WIDTH * 4)
    return unless @show_overlays

    unless fps_queue.empty?
      gb_fps = fps_queue.pop until fps_queue.empty?
      @last_speed_ratio = gb_fps / TARGET_GB_FPS
    end
    speed_ratio = @last_speed_ratio || 0.0

    @overlays[:top].update(@tick, format('Emu speed: %<speed_ratio>.2fx  FPS: %<fps>d', speed_ratio:, fps: @fps_counter.last_fps))
    buffered_audio_ms = audio_sampler ? ((audio_sampler.buffered_ms / 5).round * 5) : 0
    @overlays[:bottom].update(@tick, format('Audio buffer: %<audio>d ms', audio: buffered_audio_ms))

    draw_save_state_status
  end

  # Flashed only when the message changes: the status itself stays set once a slot has been used.
  def draw_save_state_status
    status = save_state_ui&.status
    return if status.nil? || status == @last_save_state_status

    @last_save_state_status = status
    @overlays[:save_state].flash(@tick, status)
    @overlays[:save_state_help].flash(@tick, SAVE_STATE_HELP)
  end

  class Overlay
    UPDATE_INTERVAL = 30

    attr_reader :texture, :rect

    # rubocop:disable-next Metrics/ParameterLists
    def initialize(renderer:, x:, y_origin:, text_color:, font:, align: :left, ttl: nil)
      @renderer = renderer
      @x = x
      @y_origin = y_origin
      @text_color = text_color
      @font = font
      @align = align
      @ttl = ttl

      @content = ''
      @last_update = 0
      @texture = nil
      @rect = nil
      @expires_at = nil
    end

    def update(new_tick, new_content)
      return unless updatable?(new_content:, new_tick:)

      @last_update = new_tick
      render(new_content)
    end

    def flash(tick, content)
      render(content) unless content == @content
      @expires_at = tick + @ttl
    end

    def visible?(tick) = !texture.nil? && (@expires_at.nil? || tick < @expires_at)

    private

    def updatable?(new_content:, new_tick:)
      @content != new_content && @last_update + UPDATE_INTERVAL < new_tick
    end

    def render(content)
      surface_ptr = SDL.TTF_RenderText_Solid(@font, content, @text_color)
      return if surface_ptr.null?

      @content = content
      update_texture(surface_ptr)
      update_rect(surface_ptr)

      SDL.FreeSurface(surface_ptr)
    end

    def update_texture(surface_ptr)
      SDL.DestroyTexture(@texture) if @texture
      @texture = SDL.CreateTextureFromSurface(@renderer, surface_ptr)
    end

    def update_rect(surface_ptr)
      surface = SDL::Surface.new(surface_ptr)
      height = surface[:h]
      margin_offset = (BORDER - height) / 2

      @rect = SDL::Rect.new.tap do |r|
        r[:x] = @align == :right ? @x - surface[:w] : @x
        r[:y] = @y_origin + margin_offset
        r[:w] = surface[:w]
        r[:h] = height
      end
    end
  end

  def draw_frame
    unless render_queue.empty?
      pixels_frame = render_queue.pop until render_queue.empty?
      @blob = pixels_frame.pack('N*')
    end

    SDL.UpdateTexture(@screen_texture, nil, @blob, WINDOW_WIDTH * 4) # * 4 = RGBA8888
  end

  # Blocking SDL functions means they will release the GVL during execution
  # It's required to use SDL::RenderPresent in a blocking manner to avoid locking the GVL for too long (1 frame)
  module SDLBlocking
    extend FFI::Library

    ffi_lib SDL.ffi_libraries.map(&:name)
    attach_function :RenderPresent, :SDL_RenderPresent, [:pointer], :void, blocking: true
  end

  def render
    SDL.RenderClear(@renderer)

    # Order matters: background first, then screen, then stats overlay on top
    SDL.RenderCopy(@renderer, @bg_texture, nil, @bg_texture_dest_rect)
    SDL.RenderCopy(@renderer, @screen_texture, nil, @screen_texture_dest_rect)
    @overlays.each_value { |overlay| SDL.RenderCopy(@renderer, overlay.texture, nil, overlay.rect) if overlay.visible?(@tick) }

    SDLBlocking.RenderPresent(@renderer) # Throttled by SDL::RENDERER_PRESENTVSYNC (~60fps)
    @fps_counter.update
  end
end
