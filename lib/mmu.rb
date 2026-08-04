# frozen_string_literal: true

require_relative 'apu'

# GameBoy DMG-01 MMU Emulator en Ruby
class MMU # rubocop:disable Metrics/ClassLength
  # Adresses importantes
  ADDR_LCDC = 0xFF40
  ADDR_LCD_STAT = 0xFF41
  ADDR_SCY  = 0xFF42
  ADDR_SCX  = 0xFF43
  ADDR_LY   = 0xFF44
  ADDR_LYC  = 0xFF45
  ADDR_DMA  = 0xFF46
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
  EXTERNAL_RAM_RANGE = 0xA000..0xBFFF
  WRAM_RANGE = 0xC000..0xDFFF
  OAM_RANGE = 0xFE00..0xFE9F
  IO_RANGE = 0xFF01..0xFF7F # Exclut ADDR_INP1
  HRAM_RANGE = 0xFF80..0xFFFE
  # Memory areas indexing high byte of address with a symbol (256 values)
  ADDR_TO_MEMORY_AREA = Array.new(256).tap do |arr|
    arr.fill(:rom, 0x00..0x3F)
    arr.fill(:rom_bank, 0x40..0x7F)
    arr.fill(:vram, 0x80..0x9F)
    arr.fill(:external_ram, 0xA0..0xBF)
    arr.fill(:wram, 0xC0..0xDF)
    arr[0xFE] = :oam_or_empty   # OAM: 0xFE00..0xFE9F, empty: 0xFEA0..0xFEFF
    arr[0xFF] = :io_or_hram     # I/O: 0xFF01..0xFF7F, HRAM: 0xFF80..0xFFFE
  end.freeze
  ROM_AREAS = Array.new(256).tap do |arr|
    arr.fill(:ram_bank_enable, 0x00..0x1F)
    arr.fill(:bank_select, 0x20..0x3F)
  end.freeze
  IO_HRAM_SUBAREAS = Array.new(256).tap do |arr|
    arr[0x00] = :input
    arr.fill(:io, 0x01..0x03)
    arr[0x04] = :div_timer
    arr.fill(:io, 0x05..0x7F)
    arr.fill(:hram, 0x80..0xFE)
    arr[0xFF] = :hram # ADDR_IE
  end.freeze

  INTERRUPTS = {
    vblank: 0x40,
    lcd_stat: 0x48,
    timer: 0x50,
    serial: 0x58,
    joypad: 0x60
  }.freeze
  INTERRUPTS_NAME = INTERRUPTS.keys.freeze

  # Timers
  TAC_TO_CYCLES = [1024, 16, 64, 256].freeze

  attr_reader :rom, :rom_mbc_type, :rom_bank_count, :key_state, :debug_config, :vram_version, :dirty_apu_registers,
              :div_apu_must_increment
  attr_accessor :interrupts_enabled

  def initialize(rom_bytes, rom_mbc_type: 0, rom_bank_count: 1, debug_config: {})
    @rom = rom_bytes
    @rom_mbc_type = rom_mbc_type
    @rom_bank_count = rom_bank_count
    @debug_config = debug_config
    @key_state = nil

    @vram = Array.new(0x2000, 0) # 8KB de VRAM
    @wram = Array.new(0x2000, 0) # 8KB de WRAM
    @oam = Array.new(0xA0, 0xFF) # 160 octets d'OAM
    @io = Array.new(0x80, 0)     # 128 octets d'I/O
    @hram = Array.new(0x80, 0)   # 128 octets de HRAM (0xFF80..0xFFFF)
    @external_ram = Array.new(0x2000, 0) # 8KB de VRAM

    @timers = { div: 0, tima: 0 }

    @interrupts_enabled = false
    @oam_accessible = true
    @vram_accessible = true
    @vram_version = 0
    @active_bank = 1 # For MBC1
    @ram_bank_enabled = false # For MBC1

    # Memory optimizations
    @lcd_control = {}
    @lcd_status = {}
    @dirty_apu_registers = {}
    @div_apu_must_increment = false

    @inputs_selector = nil # nil, :direction, ou :button
  end

  def read_16(address)
    low = read(address)
    high = read(address + 1)
    (high << 8) | low
  end

  def read(addr)
    area = ADDR_TO_MEMORY_AREA[addr >> 8]

    case area
    when :rom
      @rom[addr]
    when :rom_bank
      if rom_mbc_type == 1 # MBC1
        effective_bank = @active_bank % rom_bank_count
        bank_addr = (effective_bank * RomLoader::BANK_SIZE) + (addr - RomLoader::BANK_SIZE)
      end
      @rom[bank_addr || addr]
    when :vram
      @vram_accessible ? @vram[addr - VRAM_RANGE.begin] : 0xFF
    when :external_ram
      @ram_bank_enabled ? @external_ram[addr - EXTERNAL_RAM_RANGE.begin] : 0xFF
    when :wram
      @wram[addr - WRAM_RANGE.begin]
    when :io_or_hram
      case IO_HRAM_SUBAREAS[addr & 0xFF]
      when :input
        read_inputs
      when :io, :div_timer
        @io[addr - IO_RANGE.begin]
      when :hram
        @hram[addr - HRAM_RANGE.begin]
      else
        0xFF
      end
    else
      0xFF
    end
  end

  def read_inputs
    return 0xFF if key_state.nil? # Pas d'entrée, tous les bits sont à 1

    result = 0xFF
    if @inputs_selector == :direction
      result &= ~0x01 if key_state.right
      result &= ~0x02 if key_state.left
      result &= ~0x04 if key_state.up
      result &= ~0x08 if key_state.down
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
    @lcd_control[:lcd_enable] = (x & 0x80) != 0
    @lcd_control[:window_tile_map_display_select] = (x & 0x40) != 0
    @lcd_control[:window_display_enable] = (x & 0x20) != 0
    @lcd_control[:bg_and_window_tile_data_select] = (x & 0x10) != 0
    @lcd_control[:bg_tile_map_display_select] = (x & 0x08) != 0
    @lcd_control[:obj_size] = (x & 0x04) != 0
    @lcd_control[:obj_display_enable] = (x & 0x02) != 0
    @lcd_control[:bg_display] = (x & 0x01) != 0

    @lcd_control
  end

  def read_lcd_status
    x = read(ADDR_LCD_STAT)
    @lcd_status[:lyc_interrupt_enable] = (x & 0x40) != 0
    @lcd_status[:mode_2_interrupt_enable] = (x & 0x20) != 0
    @lcd_status[:mode_1_interrupt_enable] = (x & 0x10) != 0
    @lcd_status[:mode_0_interrupt_enable] = (x & 0x08) != 0
    @lcd_status[:lyc_equals_ly] = (x & 0x04) != 0
    @lcd_status[:mode] = case x & 0x03
                         when 0 then :mode_0
                         when 1 then :mode_1
                         when 2 then :mode_2
                         when 3 then :mode_3
                         end

    @lcd_status
  end

  def read_vram(addr, length = 1)
    raise "Address #{addr.to_s(16)} is not in VRAM range" unless VRAM_RANGE.include?(addr)

    if length == 1
      @vram[addr - VRAM_RANGE.begin]
    else
      @vram[addr - VRAM_RANGE.begin, length]
    end
  end

  def read_oams
    @oam[0, 40 * 4]
  end

  def read_scroll_y
    read(ADDR_SCY)
  end

  def read_scroll_x
    read(ADDR_SCX)
  end

  def write(addr, value, force: false)
    area = ADDR_TO_MEMORY_AREA[addr >> 8]

    case area
    when :vram
      return unless @vram_accessible

      @vram[addr - VRAM_RANGE.begin] = value
      @vram_version += 1
    when :external_ram
      return unless @ram_bank_enabled

      @external_ram[addr - EXTERNAL_RAM_RANGE.begin] = value
    when :wram
      @wram[addr - WRAM_RANGE.begin] = value
    when :oam_or_empty
      return unless (0..0x9F).cover?(addr & 0xFF)
      return unless @oam_accessible

      @oam[addr - OAM_RANGE.begin] = value
    when :rom
      write_rom(addr, value)
    when :io_or_hram
      write_io_hram(addr, value, force:)
    end
  end

  def write_rom(addr, value)
    return unless rom_mbc_type == 1 # MBC1

    case ROM_AREAS[addr >> 8]
    when :bank_select
      @active_bank = value & 0x1F
      @active_bank = 1 if @active_bank.zero? # MBC1 quirk
    when :ram_bank_enable
      @ram_bank_enabled = (value & 0xF) == 0xA
    end
  end

  def write_io_hram(addr, value, force:)
    case IO_HRAM_SUBAREAS[addr & 0xFF]
    when :input
      @inputs_selector = if value & 0x10 == 0
                           :direction
                         elsif value & 0x20 == 0
                           :button
                         end
    when :div_timer
      old_div = read(ADDR_DIV)
      new_div = force ? value & 0xFF : 0 # Par défaut, l'écriture dans DIV réinitialise à 0
      @io[addr - IO_RANGE.begin] = new_div
      check_div_apu_update(old_div:, new_div:)
    when :io
      @io[addr - IO_RANGE.begin] = value

      mark_dirty(addr) if APU::REGISTERS.value?(addr)
      execute_dma(value) if addr == ADDR_DMA && value != 0
    when :hram
      @hram[addr - HRAM_RANGE.begin] = value
    end
  end

  def write_16(addr, value)
    low = value & 0xFF
    high = (value >> 8) & 0xFF
    write(addr, low)
    write(addr + 1, high)
  end

  def mark_dirty(addr)
    @dirty_apu_registers[addr] = true
  end

  def consume_dirty_apu_registers
    @dirty_apu_registers.each_key { @dirty_apu_registers[_1] = read(_1) }
    res = @dirty_apu_registers.dup
    @dirty_apu_registers.clear
    res
  end

  # DMA transfer is not supposed to be instantaneous but a good approximation
  def execute_dma(value)
    source = value << 8 # * 0x100
    (0...0xA0).each do |i|
      write(0xFE00 + i, read(source + i))
    end
    write(ADDR_DMA, 0)
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

    INTERRUPTS.sort_by { _2 }.map(&:first).find do |name|
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

  def check_div_apu_update(old_div:, new_div:)
    # bit 4 falling -> div_apu increment
    old_bit4 = (old_div & 0x10)
    new_bit4 = (new_div & 0x10)
    falling_edge = old_bit4 != 0 && new_bit4.zero?
    @div_apu_must_increment ||= falling_edge # rubocop:disable Naming/MemoizedInstanceVariableName
  end

  def consume_div_apu_increment
    tmp = @div_apu_must_increment
    @div_apu_must_increment = false
    tmp
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
    @timers[:div] += nb_cycles
    return 0 unless @timers[:div] >= 256

    @timers[:div] -= 256
    1
  end

  def cycles_to_tima_timer_increment(nb_cycles)
    tac = read(ADDR_TAC)
    return nil unless tac & 0x04 != 0 # Timer désactivé

    @timers[:tima] += nb_cycles
    increment = TAC_TO_CYCLES[tac & 0x03]

    return 0 unless @timers[:tima] >= increment

    @timers[:tima] -= increment
    1
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
