require_relative 'utils/png_writer'

# GameBoy DMG-01 PPU Emulator en Ruby
class PPU
  attr_accessor :mmu, :cycles, :scanline, :mode, :framebuffer, :tile_cache, :sprite_cache, :sprite_pixel_cache

  WINDOW_WIDTH = 160
  WINDOW_HEIGHT = 144
  BACKGROUND_WIDTH = 256
  BACKGROUND_HEIGHT = 256
  SPRITE_WIDTH = 8
  BORDER = 30
  INNER_BORDER = 5
  PIXEL_SCALE = 2

  REGULAR_SCANLINES = 0...144
  VBLANK_SCANLINES = 144...154
  MODE_2_CYCLES = 0...80
  MODE_3_CYCLES = 80...252
  MODE_0_CYCLES = 252...456

  MAX_SPRITES_PER_SCANLINE = 10

  MODES = {
    mode_2: 2, # OAM Scan
    mode_3: 3, # Pixel Transfer
    mode_0: 0, # Mode 0 (HBlank) est considéré comme le mode "normal" où le PPU est prêt à dessiner la prochaine ligne
    vblank: 1  # VBlank est un mode spécial où le PPU pause pour laisser le CPU bosser sans interférer avec l'écran
  }.freeze

  CYCLES_PER_SCANLINE = MODE_0_CYCLES.end
  TOTAL_SCANLINES = VBLANK_SCANLINES.end

  def initialize(mmu, logger: nil)
    @logger = logger
    @mmu = mmu

    @cycles = 0
    @scanline = Scanline.new(mmu:)

    @tile_cache = {}
    @sprite_cache = {}
    @sprite_pixel_cache = Array.new(WINDOW_WIDTH)

    # Compteur de ligne interne de la window (WLY) : n'avance que sur les scanlines
    # où la window a effectivement été dessinée, indépendamment de LY.
    @window_line_counter = 0
    @window_used_this_scanline = false

    @framebuffer = Framebuffer.new(WINDOW_WIDTH, WINDOW_HEIGHT)
  end

  def tick(nb_cycles)
    must_return_frame = false

    # Fastpath pour les ticks qui ne font pas changer de mode
    if nb_cycles < cycles_until_next_mode_change
      if mode == :mode_3
        nb_cycles.times do
          draw_current_dot
          self.cycles += 1
        end
      else
        self.cycles += nb_cycles
      end
      return nil
    end

    nb_cycles.times do
      draw_current_dot if mode == :mode_3

      update_cycles_and_scanline
      mode_updated = update_mode

      next unless mode_updated

      scanline.mode_updated!(mode)
      if mode == :mode_2
        refresh_sprite_and_tile_cache
        scan_and_cache_oam_sprites
        update_window_line_counter
      end
      update_memory_access
      update_lcd_stat_flags
      request_interrupts
      must_return_frame = true if mode == :vblank
    end

    framebuffer.pixels_frame if must_return_frame and lcd_control[:lcd_enable]
  end

  # Palette-agostic, the caller must supply the RGB palette to render with (see Screen::COLOR_RGBA for an example).
  def export_framebuffer_png(path, palette:)
    PngWriter.write(path, framebuffer.pixels_frame, width: WINDOW_WIDTH, height: WINDOW_HEIGHT, palette:)
  end

  private

  def refresh_sprite_and_tile_cache
    return unless mmu.vram_version != @vram_version

    @vram_version = mmu.vram_version
    tile_cache.clear
    sprite_cache.clear
  end

  def update_window_line_counter
    if scanline.value == 0
      @window_line_counter = 0
    elsif @window_used_this_scanline
      @window_line_counter += 1
    end
    @window_used_this_scanline = false
  end

  def scan_and_cache_oam_sprites
    scanline.oam_sprites = []
    scan_oam_sprites
    build_oam_sprites_cache
  end

  def cycles_until_next_mode_change
    case mode
    when :mode_2 then MODE_2_CYCLES.end - cycles
    when :mode_3 then MODE_3_CYCLES.end - cycles
    when :mode_0 then MODE_0_CYCLES.end - cycles
    when :vblank then CYCLES_PER_SCANLINE - cycles
    else 0
    end
  end

  def update_cycles_and_scanline
    self.cycles = (cycles + 1) % CYCLES_PER_SCANLINE

    return unless cycles == 0

    scanline.value = (scanline.value + 1) % TOTAL_SCANLINES
    mmu.write_lcd_ly(scanline.value)
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

    old_mode != mode
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
    mmu.write_lcd_stat_ly_equals_lyc if mode == :mode_2
    mmu.write_lcd_stat_ppu_mode(mode_int)
  end

  def request_interrupts
    mmu.set_interrupt_requested(:vblank) if mode == :vblank && cycles == 0 && scanline.value == VBLANK_SCANLINES.begin

    # LCD STAT interrupt: request_interrupts only runs on a mode transition (see #tick),
    # so each of these fires exactly once, right as the PPU enters the mode.
    lcd_stat = lcd_status
    if mode == :mode_2 && lcd_stat[:mode_2_interrupt_enable]
      mmu.set_interrupt_requested(:lcd_stat)
    elsif mode == :vblank && lcd_stat[:mode_1_interrupt_enable]
      mmu.set_interrupt_requested(:lcd_stat)
    elsif mode == :mode_0 && lcd_stat[:mode_0_interrupt_enable]
      mmu.set_interrupt_requested(:lcd_stat)
    end

    # LYC=LY interrupt
    return unless mode == :mode_2 && lcd_stat[:lyc_interrupt_enable] && lcd_stat[:lyc_equals_ly]

    mmu.set_interrupt_requested(:lcd_stat)
  end

  def scan_oam_sprites
    return unless lcd_control[:obj_display_enable]

    sprite_size = scanline.obj_size ? 16 : 8

    # Select eligibles sprites by checking if they are on the current scanline.
    # Priority is defined by the address of the OAM memory location.
    selected_sprites_count = 0
    mmu.read_oams.each_slice(4).with_index do |oam_memory, oam_index|
      y = oam_memory[0]
      y_screen = y - 16
      next unless y_screen <= scanline.value && scanline.value < y_screen + sprite_size

      scanline.oam_sprites << { oam_memory:, x: oam_memory[1] - 8, oam_index: }
      selected_sprites_count += 1

      break if selected_sprites_count >= MAX_SPRITES_PER_SCANLINE
    end
  end

  def build_oam_sprites_cache
    # Sprite cache is an array of the color/priority of the sprite at each pixel
    sprite_pixel_cache.fill(nil)

    screen_y = scanline.value
    sprite_size = scanline.obj_size ? 16 : 8
    tile_data_size = sprite_size * 2 # 16 ou 32

    scanline.oam_sprites.sort_by { [_1[:x], _1[:oam_index]] }.each do |oam_sprite|
      oam_memory = oam_sprite[:oam_memory]
      base_x = oam_sprite[:x]
      base_y = oam_memory[0] - 16
      x_flipped = oam_memory[3] & 0x20 != 0
      y_flipped = oam_memory[3] & 0x40 != 0
      priority = oam_memory[3] & 0x80 == 0 ? 0 : 1
      obp_index = oam_memory[3] & 0x10 == 0 ? 0 : 1

      sprite_y = screen_y - base_y
      sprite_y = sprite_size - 1 - sprite_y if y_flipped

      tile_index = scanline.obj_size ? oam_memory[2] & 0xFE : oam_memory[2]
      tile_addr = scanline.sprite_addr(tile_index)
      tile = sprite_cache[[tile_addr, tile_data_size]] ||= Tile.new(data: mmu.read_vram(tile_addr, tile_data_size))

      SPRITE_WIDTH.times do |dx|
        screen_x = base_x + dx
        next if screen_x < 0 || screen_x >= WINDOW_WIDTH
        next if sprite_pixel_cache[screen_x]

        tile_x = x_flipped ? 7 - dx : dx
        color = tile.pixel_color(tile_x, sprite_y)
        next if color == 0

        sprite_pixel_cache[screen_x] = [color, priority, obp_index]
      end
    end
  end

  def draw_current_dot
    return unless scanline.lcd_enabled

    screen_x = cycles - MODE_3_CYCLES.begin
    screen_y = scanline.value

    sprite_pixel_color, sprite_pixel_priority, sprite_obp_index = sprite_pixel_cache[screen_x]

    window_x = screen_x - (scanline.wx - 7)
    bg_color = if scanline.window_enabled && screen_y >= scanline.wy && window_x >= 0
                 @window_used_this_scanline = true
                 compute_window_pixel(window_x)
               else
                 compute_background_pixel(screen_x, screen_y)
               end

    color =
      if !sprite_pixel_color
        scanline.bg_palette[bg_color]
      elsif sprite_pixel_priority == 1 && bg_color != 0
        scanline.bg_palette[bg_color]
      else
        obj_palette = sprite_obp_index == 1 ? scanline.obj_palette1 : scanline.obj_palette0
        obj_palette[sprite_pixel_color]
      end

    framebuffer.set_pixel(screen_x, screen_y, color)
  end

  def compute_background_pixel(screen_x, screen_y)
    bg_x = (screen_x + scanline.scx) % BACKGROUND_WIDTH
    bg_y = (screen_y + scanline.scy) % BACKGROUND_HEIGHT
    tile_x = bg_x / 8
    tile_y = bg_y / 8

    tile_index = mmu.read_vram(scanline.bg_tile_map_addr + (tile_y * 32) + tile_x)
    tile_addr = scanline.tile_addr(tile_index)
    tile = tile_cache[tile_addr] ||= Tile.new(data: mmu.read_vram(tile_addr, 16))

    tile.pixel_color(bg_x % 8, bg_y % 8)
  end

  def compute_window_pixel(window_x)
    win_y = @window_line_counter
    tile_x = window_x / 8
    tile_y = win_y / 8

    tile_index = mmu.read_vram(scanline.window_tile_map_addr + (tile_y * 32) + tile_x)
    tile_addr = scanline.tile_addr(tile_index)
    tile = tile_cache[tile_addr] ||= Tile.new(data: mmu.read_vram(tile_addr, 16))

    tile.pixel_color(window_x % 8, win_y % 8)
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
    attr_accessor :lines

    def initialize(data:)
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

  class BPPDecoder
    attr_reader :pixels

    def initialize(byte1, byte2)
      @pixels = []
      (0...8).each do |x|
        bit1 = (byte1 >> (7 - x)) & 0x01
        bit2 = (byte2 >> (7 - x)) & 0x01
        color_value = (bit2 << 1) | bit1
        @pixels << color_value
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
      @pixels = Array.new(height * width) { 0 }
    end

    def set_pixel(x, y, color)
      @pixels[(y * width) + x] = color
    end

    def get_pixel(x, y)
      @pixels[(y * width) + x]
    end

    def pixels_frame
      @pixels.dup
    end
  end

  class Scanline
    TILE_DATA_ADDRS = [0x8000, 0x9000]

    attr_accessor :value, :scx, :scy, :oam_sprites, :mmu, :bg_tile_map_addr, :tile_data_addr, :sprite_data_addr, :lcd_enabled,
                  :obj_size, :wx, :wy, :window_enabled, :window_tile_map_addr, :bg_palette, :obj_palette0, :obj_palette1

    def initialize(mmu:)
      @value = 0
      @scx = 0
      @scy = 0
      @oam_sprites = []

      @mmu = mmu
    end

    def mode_updated!(new_mode)
      return unless new_mode == :mode_2

      self.scx = mmu.read_scroll_x
      self.scy = mmu.read_scroll_y

      lcdc = mmu.read_lcd_control
      self.bg_tile_map_addr = lcdc[:bg_tile_map_display_select] ? 0x9C00 : 0x9800
      self.tile_data_addr   = lcdc[:bg_and_window_tile_data_select] ? 0x8000 : 0x9000
      self.sprite_data_addr = 0x8000
      self.obj_size = lcdc[:obj_size]
      self.lcd_enabled = lcdc[:lcd_enable]

      self.wx = mmu.read_window_x
      self.wy = mmu.read_window_y
      self.window_enabled = lcdc[:window_display_enable]
      self.window_tile_map_addr = lcdc[:window_tile_map_display_select] ? 0x9C00 : 0x9800

      self.bg_palette = mmu.read_bg_palette
      self.obj_palette0 = mmu.read_obj_palette0
      self.obj_palette1 = mmu.read_obj_palette1
    end

    def tile_addr(tile_index)
      return tile_data_addr + (tile_index * 16) if tile_data_addr == 0x8000

      tile_data_addr + ((tile_index < 128 ? tile_index : tile_index - 256) * 16)
    end

    def sprite_addr(tile_index)
      sprite_data_addr + (tile_index * 16)
    end
  end
end
