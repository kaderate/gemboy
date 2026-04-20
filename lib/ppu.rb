# GameBoy DMG-01 PPU Emulator en Ruby
class PPU
  attr_accessor :mmu, :cycles, :scanline, :mode, :framebuffer, :tile_cache

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

      if mode_updated
        if mode == :mode_2
          tile_cache.clear
          scanline.oam_sprites = []
          scan_oam_sprites
        end
        scanline.mode_updated!(mode)
        update_memory_access
        update_lcd_stat_flags
        request_interrupts
        must_return_frame = true if mode == :vblank
      end
    end

    framebuffer.pixels_frame if must_return_frame and lcd_control[:lcd_enable]
  end

  private

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

    if cycles == 0
      scanline.value = (scanline.value + 1) % TOTAL_SCANLINES
      mmu.write_lcd_ly(scanline.value)
    end
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
    mmu.write_lcd_stat_ly_equals_lyc if mode == :mode_2
    mmu.write_lcd_stat_ppu_mode(mode_int)
  end

  def request_interrupts
    if mode == :vblank && cycles == 0 && scanline.value == VBLANK_SCANLINES.begin
      mmu.set_interrupt_requested(:vblank)
    end

    # LCD STAT interrupt
    lcd_stat = self.lcd_status
    if mode == :mode_2 && lcd_stat[:mode_2_interrupt_enable] && cycles == MODE_2_CYCLES.end - 1
      mmu.set_interrupt_requested(:lcd_stat)
    elsif mode == :vblank && lcd_stat[:mode_1_interrupt_enable] && cycles == 0
      mmu.set_interrupt_requested(:lcd_stat)
    elsif mode == :mode_0 && lcd_stat[:mode_0_interrupt_enable] && cycles == MODE_0_CYCLES.end - 1
      mmu.set_interrupt_requested(:lcd_stat)
    end

    # LYC=LY interrupt
    if mode == :mode_2 && lcd_stat[:lyc_interrupt_enable] && lcd_stat[:lyc_equals_ly]
      mmu.set_interrupt_requested(:lcd_stat)
    end
  end

  def scan_oam_sprites
    return unless lcd_control[:obj_display_enable]

    sprite_size = scanline.obj_size ? 16 : 8

    # Select eligibles sprites by checking if they are on the current scanline.
    # Priority is defined by the address of the OAM memory location.
    selected_sprites_count = 0
    mmu.read_oams.each_slice(4).each do |oam_memory|
      y = oam_memory[0]
      y_screen = y - 16
      next unless y_screen <= scanline.value && scanline.value < y_screen + sprite_size

      scanline.oam_sprites << { oam_memory:, tile: nil }
      selected_sprites_count += 1

      break if selected_sprites_count >= MAX_SPRITES_PER_SCANLINE
    end
  end

  def draw_current_dot
    return unless scanline.lcd_enabled

    screen_x = cycles - MODE_3_CYCLES.begin
    screen_y = scanline.value

    # TODO render window
    sprite_pixel = compute_sprites_pixel(screen_x, screen_y)
    bg_color = compute_background_pixel(screen_x, screen_y)

    color =
      if !sprite_pixel || sprite_pixel[:color] == 0
        bg_color
      elsif sprite_pixel[:priority] == 1 && bg_color != 0
        bg_color
      else
        sprite_pixel[:color]
      end

    framebuffer.set_pixel(screen_x, screen_y, color)
  end

  # @returns { color: , priority:, ... }
  def compute_sprites_pixel(screen_x, screen_y)
    sprite_size = scanline.obj_size ? 16 : 8

    scanline.oam_sprites.filter_map.with_index do |oam_sprite, oam_index|
      oam_memory, tile = oam_sprite[:oam_memory], oam_sprite[:tile]

      x = oam_memory[1] - 8
      y = oam_memory[0] - 16
      next unless x <= screen_x && screen_x < x + 8
      next unless y <= screen_y && screen_y < y + sprite_size

      if tile.nil?
        tile_index = oam_memory[2]
        tile_data = mmu.read_vram(scanline.sprite_data_addr + tile_index * 16, 16)
        tile = Tile.new(data: tile_data)
        oam_sprite[:tile] = tile
      end

      x_flipped = oam_memory[3] & 0x20 != 0
      y_flipped = oam_memory[3] & 0x40 != 0
      sprite_x = screen_x - x
      sprite_y = screen_y - y
      sprite_x = x_flipped ? 7 - sprite_x : sprite_x
      sprite_y = y_flipped ? 7 - sprite_y : sprite_y
      color = tile.pixel_color(sprite_x, sprite_y)

      { oam_index:, x:, color:, priority: oam_memory[3] & 0x80 == 0 ? 0 : 1 }
    end.sort_by { [_1[:x], _1[:oam_index]] }.first
  end

  def compute_background_pixel(screen_x, screen_y)
    bg_x = (screen_x + scanline.scx) % BACKGROUND_WIDTH
    bg_y = (screen_y + scanline.scy) % BACKGROUND_HEIGHT

    get_tile_color(bg_x, bg_y)
  end

  def get_tile_color(bg_x, bg_y)
    tile_x = bg_x / 8
    tile_y = bg_y / 8

    tile_index = mmu.read_vram(scanline.bg_tile_map_addr + tile_y * 32 + tile_x)

    tile = tile_cache[tile_index] ||= Tile.new(data: mmu.read_vram(scanline.tile_addr(tile_index), 16))

    tile.pixel_color(bg_x % 8, bg_y % 8)
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
      return unless x.between?(0, width - 1) && y.between?(0, height - 1) # off-screen check

      @pixels[y * width + x] = color
    end

    def get_pixel(x, y)
      @pixels[y * width + x]
    end

    def pixels_frame
      @pixels.dup
    end
  end

  class Scanline
    TILE_DATA_ADDRS = [0x8000, 0x9000]

    attr_accessor :value, :scx, :scy, :oam_sprites, :mmu, :bg_tile_map_addr, :tile_data_addr, :sprite_data_addr, :lcd_enabled, :obj_size

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
    end

    def tile_addr(tile_index)
      return tile_data_addr + tile_index * 16 if tile_data_addr == 0x8000

      tile_data_addr + (tile_index < 128 ? tile_index : tile_index - 128) * 16
    end
  end
end
