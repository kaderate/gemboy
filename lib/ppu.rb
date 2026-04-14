require 'ruby2d'

# GameBoy DMG-01 PPU Emulator en Ruby
class PPU
  attr_accessor :mmu, :cycles, :scanline, :mode, :framebuffer, :tile, :tile_displayer

  WINDOW_WIDTH = 160
  WINDOW_HEIGHT = 144
  BACKGROUND_WIDTH = 256
  BACKGROUND_HEIGHT = 256
  BORDER = 30
  INNER_BORDER = 5
  PIXEL_SCALE = 2

  REGULAR_SCANLINES = 0...144
  VBLANK_SCANLINES = 144...154
  MODE_2_CYCLES = 0...80
  MODE_3_CYCLES = 80...252
  MODE_0_CYCLES = 252...456

  MODES = {
    mode_2: 2, # OAM Scan
    mode_3: 3, # Pixel Transfer
    mode_0: 0, # Mode 0 (HBlank) est considéré comme le mode "normal" où le PPU est prêt à dessiner la prochaine ligne
    vblank: 1  # VBlank est un mode spécial où le PPU pause pour laisser le CPU bosser sans interférer avec l'écran
  }.freeze

  CYCLES_PER_SCANLINE = MODE_0_CYCLES.end

  def initialize(mmu, logger: nil)
    @logger = logger
    @mmu = mmu

    @cycles = 0
    @scanline = Scanline.new(mmu:)

    @tile = nil
    @tile_displayer = nil

    @framebuffer = Framebuffer.new(WINDOW_WIDTH, WINDOW_HEIGHT)

    initialize_mode_accessors
  end

  def tick(nb_cycles)
    for_each_cycles_and_scanline(nb_cycles) { process_scanline_dot }
  end

  private

  def initialize_mode_accessors
    MODES.keys.each { |name| define_singleton_method("#{name}?") { mode == name } }
  end

  def for_each_cycles_and_scanline(nb_cycles)
    must_return_frame = false

    nb_cycles.times do
      yield if block_given?

      update_cycles_and_scanline
      mode_updated = update_mode

      if mode_updated
        scanline.mode_updated!(mode)
        update_memory_access
        update_lcd_stat_flags
        request_interrupts
      end

      must_return_frame ||= mode_updated && vblank?
    end

    framebuffer.pixels_frame if must_return_frame
  end

  def update_cycles_and_scanline
    new_cycles = cycles + 1
    self.cycles = new_cycles % CYCLES_PER_SCANLINE

    scanline.next! if new_cycles >= CYCLES_PER_SCANLINE
  end

  def update_mode
    old_mode = mode
    self.mode = case scanline.value
                when REGULAR_SCANLINES
                  case cycles
                  when MODE_2_CYCLES then :mode_2
                  when MODE_3_CYCLES then :mode_3
                  when MODE_0_CYCLES then :mode_0
                  end
                when VBLANK_SCANLINES then :vblank
                end

    return old_mode != mode
  end

  def update_memory_access
    unless lcd_control[:lcd_enable]
      mmu.set_accessible_memory(oam: true, vram: true)
      return
    end

    case mode
    when :mode_2 then mmu.set_accessible_memory(oam: false, vram: true)
    when :mode_3 then mmu.set_accessible_memory(oam: false, vram: false)
    when :mode_0, :vblank then mmu.set_accessible_memory(oam: true, vram: true)
    end
  end

  def update_lcd_stat_flags
    mmu.write_lcd_stat_ly_equals_lyc
    mmu.write_lcd_stat_ppu_mode(mode_int)
  end

  def request_interrupts
    if vblank? && cycles == 0 && scanline.value == VBLANK_SCANLINES.begin
      logi "Requesting VBlank interrupt"
      mmu.set_interrupt_requested(:vblank)
    end

    # LCD STAT interrupt
    lcd_stat = self.lcd_status
    if mode_2? && lcd_stat[:mode_2_interrupt_enable] && cycles == MODE_2_CYCLES.end - 1
      logw "Requesting LCD STAT interrupt for Mode 2"
      mmu.set_interrupt_requested(:lcd_stat)
    elsif vblank? && lcd_stat[:mode_1_interrupt_enable] && cycles == 0
      logw "Requesting LCD STAT interrupt for Mode 1 (VBlank)"
      mmu.set_interrupt_requested(:lcd_stat)
    elsif mode_0? && lcd_stat[:mode_0_interrupt_enable] && cycles == MODE_0_CYCLES.end - 1
      logw "Requesting LCD STAT interrupt for Mode 0"
      mmu.set_interrupt_requested(:lcd_stat)
    end

    # LYC=LY interrupt
    if lcd_stat[:lyc_interrupt_enable] && lcd_stat[:lyc_equals_ly]
      logw "Requesting LCD STAT interrupt for LYC=LY"
      mmu.set_interrupt_requested(:lcd_stat)
    end
  end

  def process_scanline_dot
    # update_screen if lcd_control[:lcd_enable]
    case mode
    when :mode_2
      # TODO: scan_oam_sprites
    when :mode_3
      draw_current_dot
    end
  end

  def draw_current_dot
    screen_coords = Coord.new(cycles - MODE_3_CYCLES.begin, scanline.value)

    render_current_background_tile(screen_coords)
    # TODO render window
    # TODO render sprites
  end

  def render_current_background_tile(screen_coords)
    bg_x = (screen_coords.x + scanline.scx) % BACKGROUND_WIDTH
    bg_y = (screen_coords.y + scanline.scy) % BACKGROUND_HEIGHT
    bg_coords = Coord.new(bg_x, bg_y)

    update_tile(screen_coords, bg_coords)
    update_tile_displayer(screen_coords, bg_coords)
  end

  def update_tile(screen_coords, bg_coords)
    tile_coords = Coord.new(bg_coords.x / 8, bg_coords.y / 8)
    return if tile&.coords == tile_coords

    tile_index = compute_current_tile_index(tile_coords)
    tile_data = read_tile_data(tile_index)

    @tile ||= Tile.new
    tile.update(data: tile_data, tile_coords:)
  end

  def update_tile_displayer(screen_coords, bg_coords)
    @tile_displayer ||= TileDisplayer.new(framebuffer:)
    tile_displayer.update(tile:, screen_coords:, bg_coords:).display
  end

  def compute_current_tile_index(tile_coords)
    mmu.read_vram(bg_tile_map_display_select + tile_coords.y * 32 + tile_coords.x)
  end

  def read_tile_data(tile_index)
    mmu.read_vram(tile_data_base_address + tile_index * 16, 16) # 16 bytes per tile
  end

  def tile_data_base_address
    lcd_control[:bg_and_window_tile_data_select] ? 0x8000 : 0x8800
  end

  def bg_tile_map_display_select
    lcd_control[:bg_tile_map_display_select] ? 0x9C00 : 0x9800
  end

  def lcd_control = mmu.read_lcd_control

  def lcd_status = mmu.read_lcd_status

  def mode_int
    MODES[mode]
  end

  def logw(message)
    @logger&.warn "*** [PPU] #{message}"
  end

  def logi(message)
    @logger&.info "*** [PPU] #{message}"
  end

  class Tile
    attr_accessor :lines, :coords

    def update(data:, tile_coords:)
      @coords = tile_coords
      @lines = initialize_lines(data)
    end

    def pixel_color(x, y)
      lines[y][x]
    end

    private

    def initialize_lines(data)
      res = []
      data.each_slice(2) do |byte1, byte2|
        # Decoder les 2 bytes pour obtenir les couleurs des 8 pixels de la ligne
        res << BPPDecoder.new(byte1, byte2)
      end
      res
    end
  end

  class TileDisplayer
    attr_accessor :tile, :x, :y, :x_in_screen, :y_in_screen, :framebuffer

    def initialize(framebuffer:)
      @framebuffer = framebuffer
    end

    def update(tile:, screen_coords:, bg_coords:)
      @tile = tile
      @x = bg_coords.x % 8
      @y = bg_coords.y % 8
      @x_in_screen = screen_coords.x
      @y_in_screen = screen_coords.y
      self
    end

    def display
      base_color = tile.pixel_color(x, y)
      color = self.class.hex_color_from_value(base_color)
      framebuffer.set_pixel(x_in_screen, y_in_screen, color)
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

  class Framebuffer < Struct.new(:width, :height)
    attr_reader :pixels

    def initialize(width, height)
      super
      @pixels = Array.new(height) { Array.new(width, 0xFF) }
    end

    def set_pixel(x, y, color)
      return unless x.between?(0, width - 1) && y.between?(0, height - 1) # off-screen check

      @pixels[y][x] = color
    end

    def get_pixel(x, y)
      @pixels[y][x]
    end

    def pixels_frame
      pixels.map(&:dup) # Return a copy of the pixels array to prevent external mutation
    end
  end

  class Scanline
    TOTAL_SCANLINES = VBLANK_SCANLINES.end

    attr_accessor :value, :scx, :scy, :oam_sprites, :mmu

    def initialize(mmu:)
      @value = 0
      @scx = 0
      @scy = 0
      @oam_sprites = []

      @mmu = mmu
    end

    def next!
      self.value = (value + 1) % TOTAL_SCANLINES

      update_lcd_ly
    end

    def mode_updated!(new_mode)
      update_scanline_values if new_mode == :mode_2
    end

    private

    def update_lcd_ly
      mmu.write_lcd_ly(value)
    end

    def update_scanline_values
      self.scx = mmu.read_scroll_x
      self.scy = mmu.read_scroll_y
    end
  end

  class Coord < Struct.new(:x, :y)
    def to_s
      "(#{x}, #{y})"
    end
  end
end
