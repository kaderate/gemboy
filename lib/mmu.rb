# frozen_string_literal: true

require 'forwardable'
require_relative 'apu'
require_relative 'rom_loader'
require_relative 'battery_ram'

# GameBoy DMG-01 MMU Emulator en Ruby
class MMU # rubocop:disable Metrics/ClassLength
  extend Forwardable

  # Adresses importantes
  ADDR_LCDC = 0xFF40
  ADDR_LCD_STAT = 0xFF41
  ADDR_SCY  = 0xFF42
  ADDR_SCX  = 0xFF43
  ADDR_LY   = 0xFF44
  ADDR_LYC  = 0xFF45
  ADDR_DMA  = 0xFF46
  ADDR_WY   = 0xFF4A
  ADDR_WX   = 0xFF4B
  ADDR_BGP  = 0xFF47
  ADDR_OBP0 = 0xFF48
  ADDR_OBP1 = 0xFF49
  ADDR_INP1 = 0xFF00
  # Port série (pas de câble link réel : voir debug_config[:mmu_serial])
  ADDR_SB   = 0xFF01
  ADDR_SC   = 0xFF02
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

  # Bornes précalculées (évite un appel Range#begin à chaque accès mémoire, cf profiling YJIT :
  # ce site est visité des dizaines de millions de fois par run)
  VRAM_RANGE_BEGIN = VRAM_RANGE.begin
  # Les données de tuile (bitmaps) vivent en 0x8000-0x97FF ; la tilemap (indices de tuile)
  # vit en 0x9800-0x9FFF. Seule une écriture dans la première zone change le contenu d'une
  # tuile déjà décodée (PPU#tile_cache/#sprite_cache, indexés par adresse de donnée de tuile) --
  # une écriture tilemap ne fait que changer QUELLE tuile est affichée, pas SON contenu.
  VRAM_TILE_DATA_END = 0x97FF
  EXTERNAL_RAM_RANGE_BEGIN = EXTERNAL_RAM_RANGE.begin
  WRAM_RANGE_BEGIN = WRAM_RANGE.begin
  OAM_RANGE_BEGIN = OAM_RANGE.begin
  IO_RANGE_BEGIN = IO_RANGE.begin
  HRAM_RANGE_BEGIN = HRAM_RANGE.begin
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
  ROM_AREAS_MBC1 = Array.new(256).tap do |arr|
    arr.fill(:ram_bank_enable, 0x00..0x1F)
    arr.fill(:bank_select, 0x20..0x3F)
    arr.fill(:bank_select_secondary, 0x40..0x5F)
    arr.fill(:banking_mode, 0x60..0x7F)
  end.freeze
  ROM_AREAS_MBC5 = Array.new(256).tap do |arr|
    arr.fill(:ram_bank_enable, 0x00..0x1F)
    arr.fill(:bank_select_low, 0x20..0x2F)
    arr.fill(:bank_select_high, 0x30..0x3F)
    arr.fill(:ram_bank_select, 0x40..0x5F)
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
  attr_accessor :interrupts_enabled, :external_ram

  def_delegators :cartridge_config, :rom_bank_count, :ram_bank_count

  DEFAULT_CARTRIDGE_CONFIG = RomLoader::CartridgeConfig.new(mbc: 0, rom_declared_size: 0, rom_bank_count: 1,
                                                            ram_bank_count: 0).freeze

  # Construit une MMU directement à partir d'un RomLoader::Cartridge (rom_bytes + cartridge_config),
  # pour éviter de dépaqueter le struct à chaque call site (Engine, RomTestRunner, ...).
  def self.from_cartridge(cartridge, debug_config: {})
    saved_ram = BatteryRAM.load(cartridge.battery_ram_path) if cartridge.with_battery?
    battery_ram_path = cartridge.battery_ram_path
    new(cartridge.rom_bytes, cartridge_config: cartridge.cartridge_config, debug_config:, saved_ram:, battery_ram_path:)
  end

  def initialize(rom_bytes, cartridge_config: DEFAULT_CARTRIDGE_CONFIG, debug_config: {}, saved_ram: nil, battery_ram_path: nil)
    @rom = rom_bytes
    @cartridge_config = cartridge_config
    @battery_ram_path = battery_ram_path
    @debug_config = debug_config
    @key_state = nil
    @mbc1 = cartridge_config.mbc1?
    @mbc5 = cartridge_config.mbc5?

    @vram = Array.new(0x2000, 0) # 8KB de VRAM
    @wram = Array.new(0x2000, 0) # 8KB de WRAM
    @oam = Array.new(0xA0, 0xFF) # 160 octets d'OAM
    @io = Array.new(0x80, 0)     # 128 octets d'I/O
    @hram = Array.new(0x80, 0)   # 128 octets de HRAM (0xFF80..0xFFFF)
    ram_size_bytes = ram_bank_count * RomLoader::RAM_BANK_SIZE
    @external_ram = saved_ram || Array.new(ram_size_bytes, 0) # 8KB de VRAM or more depending on the cartridge

    @timers = { div: 0, tima: 0 }

    @interrupts_enabled = false
    @oam_accessible = true
    @vram_accessible = true
    @vram_version = 0
    @active_bank = 1
    @ram_bank_enabled = cartridge_config.mbc.zero? && ram_bank_count.positive?
    @banking_mode = 0
    @secondary_bank = 0

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

  def read(addr) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
    area = ADDR_TO_MEMORY_AREA[addr >> 8]

    case area
    when :rom
      addr += ((@secondary_bank << 5) * RomLoader::ROM_BANK_SIZE) if @mbc1 && @banking_mode == 1
      @rom[addr]
    when :rom_bank
      if @mbc1
        effective_bank = (@active_bank | (@secondary_bank << 5)) % rom_bank_count
        bank_addr = (effective_bank * RomLoader::ROM_BANK_SIZE) + (addr - RomLoader::ROM_BANK_SIZE)
      elsif @mbc5
        bank_addr = ((@active_bank % rom_bank_count) * RomLoader::ROM_BANK_SIZE) + (addr - RomLoader::ROM_BANK_SIZE)
      end
      @rom[bank_addr || addr]
    when :vram
      @vram_accessible ? @vram[addr - VRAM_RANGE_BEGIN] : 0xFF
    when :external_ram
      return 0xFF unless @ram_bank_enabled

      addr += (@secondary_bank * RomLoader::RAM_BANK_SIZE) if ram_banked?
      @external_ram[addr - EXTERNAL_RAM_RANGE_BEGIN]
    when :wram
      @wram[addr - WRAM_RANGE_BEGIN]
    when :io_or_hram
      case IO_HRAM_SUBAREAS[addr & 0xFF]
      when :input
        read_inputs
      when :io, :div_timer
        @io[addr - IO_RANGE_BEGIN]
      when :hram
        @hram[addr - HRAM_RANGE_BEGIN]
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
    @lcd_control[:lcd_enable] = x.anybits?(0x80)
    @lcd_control[:window_tile_map_display_select] = x.anybits?(0x40)
    @lcd_control[:window_display_enable] = x.anybits?(0x20)
    @lcd_control[:bg_and_window_tile_data_select] = x.anybits?(0x10)
    @lcd_control[:bg_tile_map_display_select] = x.anybits?(0x08)
    @lcd_control[:obj_size] = x.anybits?(0x04)
    @lcd_control[:obj_display_enable] = x.anybits?(0x02)
    @lcd_control[:bg_display] = x.anybits?(0x01)

    @lcd_control
  end

  def read_lcd_status
    x = read(ADDR_LCD_STAT)
    @lcd_status[:lyc_interrupt_enable] = x.anybits?(0x40)
    @lcd_status[:mode_2_interrupt_enable] = x.anybits?(0x20)
    @lcd_status[:mode_1_interrupt_enable] = x.anybits?(0x10)
    @lcd_status[:mode_0_interrupt_enable] = x.anybits?(0x08)
    @lcd_status[:lyc_equals_ly] = x.anybits?(0x04)
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
      @vram[addr - VRAM_RANGE_BEGIN]
    else
      @vram[addr - VRAM_RANGE_BEGIN, length]
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

  def read_window_y
    read(ADDR_WY)
  end

  def read_window_x
    read(ADDR_WX)
  end

  def read_bg_palette
    decode_palette(read(ADDR_BGP))
  end

  def read_obj_palette0
    decode_palette(read(ADDR_OBP0))
  end

  def read_obj_palette1
    decode_palette(read(ADDR_OBP1))
  end

  def decode_palette(byte)
    [0, 1, 2, 3].map { |i| (byte >> (i * 2)) & 0x03 }
  end

  def write(addr, value, force: false) # rubocop:disable Metrics/CyclomaticComplexity
    return complete_serial_transfer(value) if debug_config[:mmu_serial] && addr == ADDR_SC && (value & 0x80 != 0)

    area = ADDR_TO_MEMORY_AREA[addr >> 8]

    case area
    when :vram
      return unless @vram_accessible

      @vram[addr - VRAM_RANGE_BEGIN] = value
      @vram_version += 1 if addr <= VRAM_TILE_DATA_END
    when :external_ram
      return unless @ram_bank_enabled

      addr -= EXTERNAL_RAM_RANGE_BEGIN
      addr += (@secondary_bank * RomLoader::RAM_BANK_SIZE) if ram_banked?
      @external_ram[addr] = value
    when :wram
      @wram[addr - WRAM_RANGE_BEGIN] = value
    when :oam_or_empty
      return unless (0..0x9F).cover?(addr & 0xFF)
      return unless @oam_accessible

      @oam[addr - OAM_RANGE_BEGIN] = value
    when :rom, :rom_bank
      write_rom(addr, value)
    when :io_or_hram
      write_io_hram(addr, value, force:)
    end
  end

  # Complète instantanément un transfert série.
  # Sur le vrai hardware, un transfert sans pair ne se termine jamais instantanément.
  # Raccourci est réservé aux outils de test.
  def complete_serial_transfer(value)
    (@serial_output ||= +'') << read(ADDR_SB).chr
    write(ADDR_SC, value & 0x7F)
    set_interrupt_requested(:serial) if interrupts_enabled_mask[:serial]
  end

  def write_rom(addr, value)
    write_rom_mbc1(addr, value) if @mbc1
    write_rom_mbc5(addr, value) if @mbc5
  end

  def write_rom_mbc1(addr, value)
    case ROM_AREAS_MBC1[addr >> 8]
    when :bank_select
      @active_bank = value & 0x1F
      @active_bank = 1 if @active_bank.zero? # MBC1 quirk
    when :ram_bank_enable
      write_ram_bank_enable(value)
    when :bank_select_secondary
      @secondary_bank = value & 0x3
    when :banking_mode
      @banking_mode = value & 0x1
    end
  end

  def write_rom_mbc5(addr, value)
    case ROM_AREAS_MBC5[addr >> 8]
    when :ram_bank_enable
      write_ram_bank_enable(value)
    when :bank_select_low
      @active_bank = (@active_bank & 0x100) | value
    when :bank_select_high
      @active_bank = (@active_bank & 0xFF) | ((value & 0x1) << 8)
    when :ram_bank_select
      @secondary_bank = value & 0xF
    end
  end

  def write_ram_bank_enable(value)
    prev_value = @ram_bank_enabled
    @ram_bank_enabled = (value & 0xF) == 0xA

    return unless !@ram_bank_enabled && prev_value && cartridge_config.with_battery?

    BatteryRAM.save(@battery_ram_path, @external_ram)
  end

  def ram_banked?
    (@mbc1 && @banking_mode == 1) || @mbc5
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
      @io[addr - IO_RANGE_BEGIN] = new_div
      check_div_apu_update(old_div:, new_div:)
    when :io
      @io[addr - IO_RANGE_BEGIN] = value

      mark_dirty(addr) if APU::REGISTERS_INVERSE.key?(addr)
      execute_dma(value) if addr == ADDR_DMA && value != 0
    when :hram
      @hram[addr - HRAM_RANGE_BEGIN] = value
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

  def dirty_apu_registers?
    !@dirty_apu_registers.empty?
  end

  attr_reader :rom, :key_state, :debug_config, :vram_version, :div_apu_must_increment, :serial_output, :cartridge_config,
              :dirty_apu_registers
  private :dirty_apu_registers # accès direct au hash réservé aux tests (mmu.send(:dirty_apu_registers))

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

  # Equivalent bit-a-bit de (interrupts_requested_mask.values & interrupts_enabled_mask.values).any? sans alloc de Hash
  def pending_interrupts?
    (read(ADDR_IE) & read(ADDR_IF)).anybits?(0x1F)
  end

  # Contrairement à pending_interrupts?, ignore IE (utilisé pour le réveil de STOP).
  def any_interrupt_requested?
    read(ADDR_IF).anybits?(0x1F)
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
    old_div = read(ADDR_DIV)
    new_div = (old_div + cycles_to_div_increment(cycles)) & 0xFF
    @io[ADDR_DIV - IO_RANGE_BEGIN] = new_div
    check_div_apu_update(old_div:, new_div:)
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
    new_stat = stat | (ly == lyc ? 0x04 : 0x00)
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
