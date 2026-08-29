# frozen_string_literal: true

require_relative 'utils/png_writer'
require_relative 'ppu/constants'
require_relative 'ppu/bpp_decoder'
require_relative 'ppu/register_access'
require_relative 'ppu/memory'
require_relative 'ppu/memory_bus'
require_relative 'ppu/tile'
require_relative 'ppu/scanline'
require_relative 'ppu/mode'
require_relative 'ppu/sprite_scanner'
require_relative 'ppu/lcd_control'
require_relative 'ppu/lcd_status'
require_relative 'ppu/framebuffer'

# GameBoy DMG-01 PPU Emulator en Ruby
class PPU
  include RegisterAccess

  attr_accessor :mmu, :cycles, :scanline, :framebuffer, :tile_cache
  attr_reader :sprite_scanner, :lcd_control, :vram_bus, :oam_bus

  MODE_3_FIRST_CYCLE = Mode::MODE_3_CYCLES.begin

  def initialize(mmu, logger: nil)
    super()
    @logger = logger
    @mmu = mmu

    @cycles = 0
    @mode_obj = Mode.new
    @scanline = Scanline.new(ppu: self)
    @lcd_control_enabled_disabled = false # TODO: edge detector
    @lcd_control = LcdControl.new(0x0)
    @lcd_stat = LcdStatus.new(bytes: 0x0, ppu: self, mode_obj: @mode_obj)

    @vram = Memory.new(size: 0x2000, base_addr: 0x8000, initial_value: 0, dirty_range: 0x8000..VRAM_TILE_DATA_END) # 8KB of VRAM
    @oam = Memory.new(size: 0xA0, base_addr: 0xFE00, initial_value: 0xFF, empty_range: 0xA0..0xFF) # 160 bytes of OAM
    @vram_bus = MemoryBus.new(@vram)
    @oam_bus = MemoryBus.new(@oam)

    @tile_cache = {}
    @sprite_scanner = SpriteScanner.new(mmu:, ppu: self)

    # Internal window line counter (WLY) : advances only on scanlines where the window has been drawn (independently of LY)
    reset_window_line_state
    @lyc_matched = false # TODO: edge detector

    reset_tile_column_caches

    @framebuffer = Framebuffer.new(WINDOW_WIDTH, WINDOW_HEIGHT)

    load_registers
  end

  # The PPU's own internal fetch (SpriteScanner, tile rendering, debug probe) always sees real
  # memory, even while the CPU bus is locked out (see #vram_bus/#oam_bus for that).
  def read_vram(addr, length = 1) = @vram.read(addr, length)
  def dirty_vram? = @vram.dirty?
  def read_oams = @oam.read(0xFE00, 40 * 4)

  def snapshot_for_render = %i[scx scy wx wy bgp obp0 obp1].to_h { |reg| [reg, read_register(REGISTERS[reg])] }

  def mode = @mode_obj.name
  def ly = scanline.value

  def on_read(addr, read_value)
    case REGISTERS_FROM_ADDR[addr]
    when :lcd_control then @lcd_control.bytes
    when :lcd_stat then @lcd_stat.bytes
    when :ly then ly
    else read_value
    end
  end

  def on_load(addr, value)
    case REGISTERS_FROM_ADDR[addr]
    when :lcd_control then handle_lcdc_change(value)
    when :lcd_stat then @lcd_stat.bytes = value
    end
  end

  def on_write(_addr, _value) = nil

  def handle_lcdc_change(value)
    prev_lcdc_enable = lcd_control.lcd_enable
    lcd_control.bytes = value
    @lcd_control_enabled_disabled = true if prev_lcdc_enable && !lcd_control.lcd_enable
  end

  def tick(nb_cycles)
    bypass_ppu = handle_disabled_ppu
    return framebuffer.pixels_frame if bypass_ppu == :bypass_and_render
    return nil if bypass_ppu == :bypass

    must_return_frame = false

    # Fastpath when no mode change
    return tick_fast_path(nb_cycles) if nb_cycles < cycles_until_next_mode_change

    nb_cycles.times do
      draw_current_dot if mode == :mode_3

      scanline_changed = update_cycles_and_scanline
      mode_updated = update_mode

      must_return_frame = handle_mode_change if mode_updated

      # LYC=LY check and related STAT interrupt must be evaluated at every scanline change (LY) (not only at mode change)
      # A LYC targeting one of these scanlines would never be detected if we only looked at mode changes.
      # We also keep mode_updated to cover the first tick (LY=0 at startup, before any scanline transition).
      request_lyc_interrupt if mode_updated || scanline_changed
    end

    framebuffer.pixels_frame if must_return_frame
  end

  def tick_fast_path(nb_cycles)
    if mode == :mode_3
      nb_cycles.times do
        draw_current_dot
        self.cycles += 1
      end
    else
      self.cycles += nb_cycles
    end

    nil
  end

  def handle_mode_change
    scanline.mode_updated!(mode)

    if mode == :mode_2
      refresh_sprite_and_tile_cache
    elsif mode == :mode_3
      # Le scan OAM doit lui aussi lire l'état LCDC tel qu'il est à la fin du mode_2 (voir
      # Scanline#mode_updated!) : une ROM peut activer obj_display_enable via une interruption
      # LYC servie en plein milieu du mode_2, et le sprite doit apparaître dès cette ligne.
      sprite_scanner.scan_and_cache(scanline:, obj_display_enable: lcd_control.obj_display_enable)
      update_window_line_counter
      reset_tile_column_caches
    end

    update_memory_access
    request_mode_interrupts

    return false unless mode == :vblank

    reset_window_line_state
    true
  end

  def handle_disabled_ppu
    # LCD just disabled: reset PPU state properly
    if @lcd_control_enabled_disabled
      @mode_obj.name = :mode_0
      @cycles = 0

      reset_ly
      reset_window_line_state
      update_memory_access

      @lcd_control_enabled_disabled = false

      # LCD just disabled: render a (white) blank frame
      framebuffer.set_pixels(0)
      return :bypass_and_render
    end

    # LCD disabled: nothing to do
    :bypass unless lcd_control.lcd_enable
  end

  def reset_ly = scanline.value = 0

  def reset_window_line_state
    @window_line_counter = 0
    @window_used_this_scanline = false
  end

  # Palette-agostic, the caller must supply the RGB palette to render with (see Screen::COLOR_RGBA for an example).
  def export_framebuffer_png(path, palette:)
    PngWriter.write(path, framebuffer.pixels_frame, width: WINDOW_WIDTH, height: WINDOW_HEIGHT, palette:)
  end

  private

  def cycles_until_next_mode_change = @mode_obj.cycles_until_next_mode_change(cycles)
  def update_mode = @mode_obj.update!(ly, cycles)

  def refresh_sprite_and_tile_cache
    return unless @vram.dirty?

    @vram.mark_as_clean!
    tile_cache.clear
    sprite_scanner.clear_cache
  end

  def reset_tile_column_caches
    # -1 plutôt que nil : tile_x est toujours >= 0, donc la sentinelle reste un Integer et le
    # site de comparaison `tile_x != @bg_tile_x_cache` (appelé par pixel) garde un type stable
    # pour YJIT au lieu d'alterner Integer/NilClass (cf profiling --yjit-stats).
    @bg_tile_x_cache = -1
    @bg_tile_cache = nil
    @win_tile_x_cache = -1
    @win_tile_cache = nil
  end

  def update_window_line_counter
    return unless @window_used_this_scanline

    @window_line_counter += 1
    @window_used_this_scanline = false
  end

  def update_cycles_and_scanline
    self.cycles = (cycles + 1) % CYCLES_PER_SCANLINE

    return false unless cycles == 0

    scanline.tick!
    true
  end

  def update_memory_access
    return set_accessible_memory(oam: true, vram: true) unless lcd_control.lcd_enable

    case mode
    when :mode_2 then set_accessible_memory(oam: false, vram: true)
    when :mode_3 then set_accessible_memory(oam: false, vram: false)
    when :mode_0, :vblank then set_accessible_memory(oam: true, vram: true)
    end
  end

  # Sources d'interruption STAT liées au mode : n'évaluées qu'à l'entrée dans le mode
  # (appelé uniquement quand mode_updated, voir #tick), donc chacune ne se déclenche
  # qu'une seule fois par entrée dans le mode correspondant.
  def request_mode_interrupts
    mmu.set_interrupt_requested(:vblank) if mode == :vblank

    mode_interrupt_enabled = (mode == :mode_2 && @lcd_stat.mode_2_interrupt_enable) ||
                             (mode == :vblank && @lcd_stat.mode_1_interrupt_enable) ||
                             (mode == :mode_0 && @lcd_stat.mode_0_interrupt_enable)
    mmu.set_interrupt_requested(:lcd_stat) if mode_interrupt_enabled
  end

  # LYC=LY : évalué à chaque changement de scanline (LY), indépendamment du mode (voir #tick),
  # car LY continue d'avancer pendant tout le VBlank sans jamais repasser par mode_2.
  #
  # Détection sur front montant, pas sur niveau : ce hook est aussi appelé à chaque transition de
  # mode (jusqu'à 3x par scanline), donc si le handler d'une interruption LYC réécrit LYC en cours
  # d'exécution (avant son RETI), une ré-évaluation qui tombe entre-temps verrait encore l'ancienne
  # correspondance et redemanderait l'interruption -- servie immédiatement au retour du RETI, ce qui
  # exécute prématurément le handler suivant de la chaîne alors que LY n'a pas encore bougé.
  def request_lyc_interrupt
    # TODO: implement a proper edge detector
    matched = @lcd_stat.lyc_equals_ly
    just_matched = matched && !@lyc_matched
    @lyc_matched = matched

    mmu.set_interrupt_requested(:lcd_stat) if just_matched && @lcd_stat.lyc_interrupt_enable
  end

  def draw_current_dot
    return unless scanline.lcd_enabled

    screen_x = cycles - MODE_3_FIRST_CYCLE
    return if screen_x >= WINDOW_WIDTH

    screen_y = ly

    sprite_pixel_color, sprite_pixel_priority, sprite_obp_index = sprite_scanner.sprite_pixel_cache[screen_x]

    # LCDC.0: when disabled, neither the background nor the window are drawn, only BGP 0 is displayed (sprites visible behind)
    bg_color =
      if scanline.bg_enabled
        window_x = screen_x - (scanline.wx - 7)
        if scanline.window_enabled && screen_y >= scanline.wy && window_x >= 0
          @window_used_this_scanline = true
          compute_window_pixel(window_x)
        else
          compute_background_pixel(screen_x, screen_y)
        end
      else
        0
      end

    color =
      if !sprite_pixel_color || (sprite_pixel_priority == 1 && bg_color != 0)
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

    if tile_x != @bg_tile_x_cache
      @bg_tile_x_cache = tile_x
      tile_y = bg_y / 8
      tile_index = read_vram(scanline.bg_tile_map_addr + (tile_y * 32) + tile_x)
      tile_addr = scanline.tile_addr(tile_index)
      @bg_tile_cache = tile_cache[tile_addr] ||= Tile.new(data: read_vram(tile_addr, 16))
    end

    @bg_tile_cache.pixel_color(bg_x % 8, bg_y % 8)
  end

  def compute_window_pixel(window_x)
    win_y = @window_line_counter
    tile_x = window_x / 8

    if tile_x != @win_tile_x_cache
      @win_tile_x_cache = tile_x
      tile_y = win_y / 8
      vram_addr = scanline.window_tile_map_addr + (tile_y * 32) + tile_x
      tile_index = read_vram(vram_addr)
      tile_addr = scanline.tile_addr(tile_index)
      @win_tile_cache = tile_cache[tile_addr] ||= Tile.new(data: read_vram(tile_addr, 16))
    end

    @win_tile_cache.pixel_color(window_x % 8, win_y % 8)
  end

  def set_accessible_memory(oam: true, vram: true)
    @oam_bus.accessible = oam
    @vram_bus.accessible = vram
  end

  def logw(message) = @logger&.warn "*** [PPU] #{message}"
  def logi(message) = @logger&.info "*** [PPU] #{message}"
end
