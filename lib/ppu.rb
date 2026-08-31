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
require_relative 'ppu/cgb_palette'
require_relative 'ppu/coordinate'
require_relative 'ppu/dot_drawer'
require_relative 'edge_detector'
require_relative 'interrupts'
require_relative 'screen'

# GameBoy DMG-01 PPU Emulator en Ruby
class PPU
  include RegisterAccess

  attr_accessor :mmu, :cycles, :scanline, :framebuffer
  attr_reader :sprite_scanner, :lcd_control, :vram, :vram_bus, :oam_bus, :interrupts, :bg_palette, :obj_palette, :oam_reader,
              :dot_drawer

  MODE_3_FIRST_CYCLE = Mode::MODE_3_CYCLES.begin

  OamReader = Struct.new(:oam) do
    def read_oams = oam.read(0xFE00, 40 * 4)
  end

  def initialize(mmu, interrupts: Interrupts.new, logger: nil)
    super()
    @logger = logger
    @mmu = mmu
    @interrupts = interrupts

    @cycles = 0
    @mode_obj = Mode.new
    @scanline = Scanline.new(ppu: self)
    @lcd_control_enabled_disabled = false
    @lcd_control = LcdControl.new(0x0)
    @lcd_stat = LcdStatus.new(bytes: 0x0, ppu: self, mode_obj: @mode_obj)

    bank = mmu.model.cgb? ? 2 : 1
    @vram = Memory.new(size: 0x2000, bank:, base_addr: 0x8000, initial_value: 0, dirty_range: 0x8000..0x9FFF)
    @oam = Memory.new(size: 0xA0, base_addr: 0xFE00, initial_value: 0xFF, empty_range: 0xA0..0xFF) # 160 bytes of OAM
    @vram_bus = MemoryBus.new(@vram)
    @oam_bus = MemoryBus.new(@oam)
    @oam_reader = OamReader.new(@oam)

    @sprite_scanner = SpriteScanner.new(mmu:, vram: @vram, oam_reader: @oam_reader)
    @bg_palette = CGBPalette.new
    @obj_palette = CGBPalette.new
    @dot_drawer = DotDrawer.for_model(mmu.model, bg_palette: @bg_palette, obj_palette: @obj_palette, scanline:, sprite_scanner:,
                                                 vram: @vram)

    # Internal window line counter (WLY) : advances only on scanlines where the window has been drawn (independently of LY)
    @dot_drawer.reset_window_line_state!
    @lyc_edge_detector = EdgeDetector.new

    @dot_drawer.reset_caches!

    @framebuffer = Framebuffer.new(WINDOW_WIDTH, WINDOW_HEIGHT)

    load_registers
  end

  def dirty_vram? = @vram.dirty?

  def snapshot_for_render = %i[scx scy wx wy bgp obp0 obp1].to_h { |reg| [reg, read_register(REGISTERS[reg])] }

  # Work differently than registers so they're routed directly rather than through #read_register/#write_register
  def read_cgb_palette(addr)
    case addr
    when 0xFF68 then bg_palette.read_index
    when 0xFF69 then bg_palette.read_data
    when 0xFF6A then obj_palette.read_index
    when 0xFF6B then obj_palette.read_data
    end
  end

  def write_cgb_palette(addr, value)
    case addr
    when 0xFF68 then bg_palette.write_index(value)
    when 0xFF69 then bg_palette.write_data(value)
    when 0xFF6A then obj_palette.write_index(value)
    when 0xFF6B then obj_palette.write_data(value)
    end
  end

  def read_cgb_register(addr)
    case addr
    when :opri then @sprite_scanner.object_priority_mode
    end
  end

  def write_cgb_register(addr, value)
    case addr
    when :opri then @sprite_scanner.object_priority_mode = (value & 0x1)
    end
  end

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
    return tick_fast_path(nb_cycles) if nb_cycles < @mode_obj.cycles_until_next_mode_change(cycles)

    nb_cycles.times do
      draw_current_dot if mode == :mode_3

      scanline_changed = update_cycles_and_scanline
      mode_updated = @mode_obj.update!(ly, cycles)

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
      @dot_drawer.update_window_line_counter!
      @dot_drawer.reset_caches!
    end

    update_memory_access
    request_mode_interrupts

    return false unless mode == :vblank

    @dot_drawer.reset_window_line_state!
    true
  end

  def handle_disabled_ppu
    # LCD just disabled: reset PPU state properly
    if @lcd_control_enabled_disabled
      @mode_obj.name = :mode_0
      @cycles = 0

      scanline.reset_ly!
      @dot_drawer.reset_window_line_state!
      update_memory_access

      @lcd_control_enabled_disabled = false

      # LCD just disabled: render a blank frame
      framebuffer.set_pixels(Screen::BG_COLOR_SDL)
      return :bypass_and_render
    end

    # LCD disabled: nothing to do
    :bypass unless lcd_control.lcd_enable
  end

  def export_framebuffer_png(path) = PngWriter.write(path, framebuffer.pixels_frame, width: WINDOW_WIDTH, height: WINDOW_HEIGHT)

  private

  def draw_current_dot
    return unless scanline.lcd_enabled

    screen_x = cycles - MODE_3_FIRST_CYCLE
    return if screen_x >= WINDOW_WIDTH

    screen_y = ly
    color = @dot_drawer.draw_current_dot(screen_x, screen_y)
    framebuffer.set_pixel(screen_x, screen_y, color)
  end

  def refresh_sprite_and_tile_cache
    return unless @vram.dirty?

    @vram.mark_as_clean!
    @dot_drawer.reset_tile_column_caches!
    sprite_scanner.clear_cache
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
    interrupts.request(:vblank) if mode == :vblank

    mode_interrupt_enabled = (mode == :mode_2 && @lcd_stat.mode_2_interrupt_enable) ||
                             (mode == :vblank && @lcd_stat.mode_1_interrupt_enable) ||
                             (mode == :mode_0 && @lcd_stat.mode_0_interrupt_enable)
    interrupts.request(:lcd_stat) if mode_interrupt_enabled
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
    just_matched = @lyc_edge_detector.rising?(@lcd_stat.lyc_equals_ly)

    interrupts.request(:lcd_stat) if just_matched && @lcd_stat.lyc_interrupt_enable
  end

  def set_accessible_memory(oam: true, vram: true)
    @oam_bus.accessible = oam
    @vram_bus.accessible = vram
  end

  def logw(message) = @logger&.warn "*** [PPU] #{message}"
  def logi(message) = @logger&.info "*** [PPU] #{message}"
end
