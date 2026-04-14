# GameBoy DMG-01 MMU Emulator en Ruby
class MMU
  # Adresses importantes
  ADDR_LCDC = 0xFF40
  ADDR_LCD_STAT = 0xFF41
  ADDR_SCY  = 0xFF42
  ADDR_SCX  = 0xFF43
  ADDR_LY   = 0xFF44
  ADDR_LYC  = 0xFF45
  ADDR_INP1 = 0xFF00
  # Interruptions (dans les plages I/O et HRAM)
  ADDR_IE   = 0xFFFF
  ADDR_IF   = 0xFF0F
  # Timers (dans la plage I/O)
  ADDR_DIV  = 0xFF04
  ADDR_TIMA = 0xFF05
  ADDR_TMA  = 0xFF06
  ADDR_TAC  = 0xFF07

  # Ranges d'adresses mappées
  ROM_RANGE = 0x0000..0x7FFF
  VRAM_RANGE = 0x8000..0x9FFF
  WRAM_RANGE = 0xC000..0xDFFF
  OAM_RANGE = 0xFE00..0xFE9F
  IO_RANGE = 0xFF01..0xFF7F # Exclut ADDR_INP1
  HRAM_RANGE = 0xFF80..0xFFFE

  INTERRUPTS = {
    vblank: 0x40,
    lcd_stat: 0x48,
    timer: 0x50,
    serial: 0x58,
    joypad: 0x60
  }.freeze
  INTERRUPTS_NAME = INTERRUPTS.keys.freeze

  attr_reader :rom, :key_state
  attr_accessor :interrupts_enabled

  def initialize(rom_bytes)
    @rom = rom_bytes
    @key_state = nil

    @vram = Array.new(0x2000, 0) # 8KB de VRAM
    @wram = Array.new(0x2000, 0) # 8KB de WRAM
    @oam = Array.new(0xA0, 0xFF) # 160 octets d'OAM
    @io = Array.new(0x80, 0)     # 128 octets d'I/O
    @hram = Array.new(0x80, 0)   # 128 octets de HRAM (0xFF80..0xFFFF)

    @interrupts_enabled = false
    @oam_accessible = true
    @vram_accessible = true

    @inputs_selector = nil # nil, :direction, ou :button
  end

  def read_16(address)
    low, high = read(address), read(address + 1)
    (high << 8) | low
  end

  def read(addr)
    case addr
    when ROM_RANGE
      @rom[addr]
    when VRAM_RANGE
      @vram_accessible ? @vram[addr - VRAM_RANGE.begin] : 0xFF
    when WRAM_RANGE
      @wram[addr - WRAM_RANGE.begin]
    when OAM_RANGE
      0xFF # @oam_accessible ? @oam[addr - OAM_RANGE.begin] : 0xFF
    when ADDR_INP1
      read_inputs
    when IO_RANGE
      @io[addr - IO_RANGE.begin]
    when HRAM_RANGE
      @hram[addr - HRAM_RANGE.begin]
    when ADDR_IE
      @hram[addr - HRAM_RANGE.begin]
    else
      0xFF # adresses non mappées
    end
  end

  def read_inputs
    return 0xFF if key_state.nil? # Pas d'entrée, tous les bits sont à 1

    result = 0xFF
    if @inputs_selector == :direction
      result &= ~0x01 if key_state.up
      result &= ~0x02 if key_state.down
      result &= ~0x04 if key_state.left
      result &= ~0x08 if key_state.right
    elsif @inputs_selector == :button
      result &= ~0x01 if key_state.a
      result &= ~0x02 if key_state.b
      result &= ~0x04 if key_state.select
      result &= ~0x08 if key_state.start
    end
    result
  end

  def read_lcd_control
    x = read(ADDR_LCDC)
    {
      lcd_enable: (x & 0x80) != 0,
      window_tile_map_display_select: (x & 0x40) != 0,
      window_display_enable: (x & 0x20) != 0,
      bg_and_window_tile_data_select: (x & 0x10) != 0,
      bg_tile_map_display_select: (x & 0x08) != 0,
      obj_size: (x & 0x04) != 0,
      obj_display_enable: (x & 0x02) != 0,
      bg_display: (x & 0x01) != 0
    }
  end

  def read_lcd_status
    x = read(ADDR_LCD_STAT)
    {
      lyc_interrupt_enable: (x & 0x40) != 0,
      mode_2_interrupt_enable: (x & 0x20) != 0,
      mode_1_interrupt_enable: (x & 0x10) != 0,
      mode_0_interrupt_enable: (x & 0x08) != 0,
      lyc_equals_ly: (x & 0x04) != 0,
      mode: case x & 0x03
            when 0 then :mode_0
            when 1 then :mode_1
            when 2 then :mode_2
            when 3 then :mode_3
            end
    }
  end

  def read_vram(addr, length = 1)
    if VRAM_RANGE.include?(addr)
      if length == 1
        @vram[addr - VRAM_RANGE.begin]
      else
        @vram[addr - VRAM_RANGE.begin, length]
      end
    else
      raise "Address #{addr.to_s(16)} is not in VRAM range"
    end
  end

  def read_scroll_y
    read(ADDR_SCY)
  end

  def read_scroll_x
    read(ADDR_SCX)
  end

  def write(addr, value, force: false)
    case addr
    when VRAM_RANGE
      @vram[addr - VRAM_RANGE.begin] = value if @vram_accessible
    when WRAM_RANGE
      @wram[addr - WRAM_RANGE.begin] = value
    when OAM_RANGE
      @oam[addr - OAM_RANGE.begin] = value if @oam_accessible
    when ADDR_INP1
      if value & 0x10 == 0
        @inputs_selector = :direction
      elsif value & 0x20 == 0
        @inputs_selector = :button
      else
        @inputs_selector = nil
      end
    when ADDR_DIV
      new_div = force ? value & 0xFF : 0 # Par défaut, l'écriture dans DIV réinitialise à 0
      @io[addr - IO_RANGE.begin] = new_div
    when IO_RANGE
      if addr == 0xff01
        char = value < 127 ? value.chr : "?"
        puts "[SERIAL_OUT] #{char.inspect} (0x#{value.to_s(16)})"
      end
      @io[addr - IO_RANGE.begin] = value
    when HRAM_RANGE
      @hram[addr - HRAM_RANGE.begin] = value
    when ADDR_IE
      @hram[addr - HRAM_RANGE.begin] = value
    else
      # ROM et adresses non mappées sont en lecture seule
    end
  end

  def interrupts_enabled_mask
    interrupt_mask(read(ADDR_IE))
  end

  def interrupts_requested_mask
    interrupt_mask(read(ADDR_IF))
  end

  def interrupt_mask(value)
    {
      vblank: value & 0x01 != 0,
      lcd_stat: value & 0x02 != 0,
      timer: value & 0x04 != 0,
      serial: value & 0x08 != 0,
      joypad: value & 0x10 != 0
    }
  end

  def most_important_interrupt
    return nil unless interrupts_enabled

    INTERRUPTS.sort_by{_2}.map(&:first).find do |name|
      interrupts_enabled_mask[name] && interrupts_requested_mask[name]
    end
  end

  def interrupt_vector(name)
    INTERRUPTS[name]
  end

  def set_interrupt_requested(name)
    check_interrupt_name(name)
    write(ADDR_IF, read(ADDR_IF) | (1 << INTERRUPTS_NAME.index(name)))
  end

  def clear_interrupt_requested(name)
    check_interrupt_name(name)
    write(ADDR_IF, read(ADDR_IF) & ~(1 << INTERRUPTS_NAME.index(name)))
  end

  def set_interrupt_enabled(name)
    check_interrupt_name(name)
    write(ADDR_IE, read(ADDR_IE) | (1 << INTERRUPTS_NAME.index(name)))
  end

  def clear_interrupt_enabled(name)
    check_interrupt_name(name)
    write(ADDR_IE, read(ADDR_IE) & ~(1 << INTERRUPTS_NAME.index(name)))
  end

  def check_interrupt_name(name)
    raise "Unknown interrupt name: #{name}" unless INTERRUPTS.key?(name)
  end

  def increment_timers(cycles)
    increment_div_timer(cycles)
    increment_tima_timer(cycles)
  end

  def increment_div_timer(cycles)
    div = read(ADDR_DIV)
    new_div = (div + cycles_to_div_increment(cycles)) & 0xFF
    write(ADDR_DIV, new_div, force: true) # évite réinitialisation à 0
  end

  def increment_tima_timer(cycles)
    increment = cycles_to_tima_timer_increment(cycles)
    return if increment.nil? # Timer désactivé

    tima = read(ADDR_TIMA)
    new_tima = (tima + increment) & 0xFF

    if new_tima < tima # Overflow
      write(ADDR_TIMA, read(ADDR_TMA))
      set_interrupt_requested(:timer)
    else
      write(ADDR_TIMA, new_tima)
    end
  end

  def cycles_to_div_increment(nb_cycles)
    nb_cycles / 256
  end

  def cycles_to_tima_timer_increment(nb_cycles)
    tac = read(ADDR_TAC)
    return nil unless tac & 0x04 != 0 # Timer désactivé

    case tac & 0x03
    when 0
      nb_cycles / 1024
    when 1
      nb_cycles / 16
    when 2
      nb_cycles / 64
    when 3
      nb_cycles / 256
    end
  end

  def set_accessible_memory(oam: nil, vram: nil)
    @oam_accessible = oam unless oam.nil?
    @vram_accessible = vram unless vram.nil?
  end

  def write_lcd_ly(value)
    write(ADDR_LY, value)
  end

  def write_lcd_stat_ly_equals_lyc
    ly = read(ADDR_LY)
    lyc = read(ADDR_LYC)

    stat = read(ADDR_LCD_STAT) & 0xFB # Clear bit 2 (LYC=LY)
    new_stat = stat | (ly === lyc ? 0x04 : 0x00)
    write(ADDR_LCD_STAT, new_stat)
  end

  def write_lcd_stat_ppu_mode(mode_int)
    stat = read(ADDR_LCD_STAT) & 0xFC # Clear bits 0 and 1 (PPU mode)
    new_stat = stat | (mode_int & 0x03)
    write(ADDR_LCD_STAT, new_stat)
  end

  def set_key_state(key_state)
    @key_state = key_state
  end
end
