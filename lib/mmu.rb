# frozen_string_literal: true

require_relative 'apu'
require_relative 'apu/null_apu'
require_relative 'cartridge_loader'
require_relative 'battery_ram'
require_relative 'boot_values'
require_relative 'mbc'
require_relative 'ppu/null_ppu'
require_relative 'timer'
require_relative 'joypad'

# GameBoy DMG-01 MMU Emulator en Ruby
class MMU
  ADDR_DMA  = 0xFF46
  # Serial port (no real link cable: see #mmu_serial)
  ADDR_SB   = 0xFF01
  ADDR_SC   = 0xFF02
  # Interruptions (in I/O et HRAM ranges)
  ADDR_IE   = 0xFFFF
  ADDR_IF   = 0xFF0F

  # Memory ranges (for documentation)
  ROM_RANGE = 0x0000..0x7FFF
  VRAM_RANGE = 0x8000..0x9FFF
  EXTERNAL_RAM_RANGE = 0xA000..0xBFFF
  WRAM_RANGE = 0xC000..0xDFFF
  OAM_RANGE = 0xFE00..0xFE9F
  IO_RANGE = 0xFF01..0xFF7F # Exclut ADDR_INP1 (0xFF00)
  HRAM_RANGE = 0xFF80..0xFFFE

  # Avoid calling Range#begin on every memory access (profiling YJIT, visited a few million times per run)
  WRAM_RANGE_BEGIN = WRAM_RANGE.begin
  IO_RANGE_BEGIN   = IO_RANGE.begin
  HRAM_RANGE_BEGIN = HRAM_RANGE.begin

  # Memory areas indexing high byte of address with a symbol
  ADDR_TO_MEMORY_AREA = Array.new(256).tap do |arr|
    arr.fill(:rom, 0x00..0x7F)
    arr.fill(:vram, 0x80..0x9F)
    arr.fill(:external_ram, 0xA0..0xBF)
    arr.fill(:wram, 0xC0..0xDF)
    arr[0xFE] = :oam_or_empty   # OAM: 0xFE00..0xFE9F, empty: 0xFEA0..0xFEFF
    arr[0xFF] = :io_or_hram     # I/O: 0xFF01..0xFF7F, HRAM: 0xFF80..0xFFFE
  end.freeze

  IO_HRAM_SUBAREAS = Array.new(256).tap do |arr|
    arr[0x00] = :input
    arr.fill(:io, 0x01..0x03)
    arr.fill(:timer, 0x04..0x07)
    arr.fill(:io, 0x08..0x0F)
    arr.fill(:apu, 0x10..0x3F)
    arr.fill(:ppu, 0x40..0x45)
    arr[0x46] = :io
    arr.fill(:ppu, 0x47..0x4B)
    arr.fill(:io, 0x4C..0x7F)
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

  attr_accessor :interrupts_enabled
  attr_reader :mmu_serial, :serial_output, :mbc, :rtc, :joypad
  attr_writer :apu

  def self.from_cartridge(cartridge, debug_config: {}, joypad: Joypad.new)
    mbc = MBC.build(cartridge, external_ram_start: EXTERNAL_RAM_RANGE.begin)
    new(mbc:, debug_config:, joypad:).tap { |mmu| mmu.initialize_io(BootValues::IO_ROM_BOOT_VALUES.dup) }
  end

  def initialize(mbc:, apu: APU::NullAPU.new, ppu: PPU::NullPPU.new, joypad: Joypad.new, debug_config: {})
    @mbc = mbc
    @rtc = mbc.rtc
    @apu = apu
    @ppu = ppu
    @mmu_serial = debug_config.fetch(:mmu_serial, false)
    @joypad = joypad
    @timer = Timer.new

    # Memory areas
    @wram = Array.new(0x2000, 0) # 8KB of WRAM
    @io   = Array.new(0x80, 0)   # 128 bytes of I/O
    @hram = Array.new(0x80, 0)   # 128 bytes of HRAM (0xFF80..0xFFFF)

    @interrupts_enabled = false
  end

  def attach_apu(apu)
    apu.registers = @apu.registers
    @apu = apu
    @apu.load_registers
  end

  def attach_ppu(ppu)
    ppu.registers = @ppu.registers
    @ppu = ppu
    @ppu.load_registers
  end

  def initialize_io(boot_io)
    boot_io.each do |addr, val|
      case IO_HRAM_SUBAREAS[addr & 0xFF]
      when :timer then @timer.write(addr, val, force: true)
      when :apu   then @apu.load(addr, val)
      when :ppu   then @ppu.load(addr, val)
      else @io[addr - IO_RANGE_BEGIN] = val
      end
    end
  end

  def read_16(address)
    low = read(address)
    high = read(address + 1)
    (high << 8) | low
  end

  def read(addr)
    case ADDR_TO_MEMORY_AREA[addr >> 8]
    when :rom          then @mbc.read_rom(addr)
    when :vram         then @ppu.vram_bus.read(addr)
    when :wram         then read_wram(addr)
    when :external_ram then @mbc.read_ram(addr)
    when :oam_or_empty then @ppu.oam_bus.read(addr)
    when :io_or_hram
      case IO_HRAM_SUBAREAS[addr & 0xFF]
      when :input then @joypad.read
      when :io    then read_io(addr)
      when :timer then @timer.read(addr)
      when :hram  then read_hram(addr)
      when :apu   then @apu.read_register(addr)
      when :ppu   then @ppu.read_register(addr)
      else
        0xFF
      end
    else
      0xFF
    end
  end

  def read_wram(addr) = @wram[addr - WRAM_RANGE_BEGIN]
  def read_io(addr) = @io[addr - IO_RANGE_BEGIN]
  def read_hram(addr) = @hram[addr - HRAM_RANGE_BEGIN]

  def write_16(addr, value)
    low = value & 0xFF
    high = (value >> 8) & 0xFF
    write(addr, low)
    write(addr + 1, high)
  end

  def write(addr, value, force: false)
    return complete_serial_transfer(value) if mmu_serial && addr == ADDR_SC && (value & 0x80 != 0)

    area = ADDR_TO_MEMORY_AREA[addr >> 8]

    case area
    when :vram         then @ppu.vram_bus.write(addr, value)
    when :external_ram then @mbc.write_ram(addr, value)
    when :wram         then write_wram(addr, value)
    when :oam_or_empty then @ppu.oam_bus.write(addr, value)
    when :rom          then @mbc.write_rom(addr, value)
    when :io_or_hram   then write_io_hram(addr, value, force:)
    end
  end

  # Complète instantanément un transfert série. Sur le vrai hardware, un transfert sans pair ne se termine jamais instantanément.
  # Raccourci est réservé aux outils de test.
  def complete_serial_transfer(value)
    (@serial_output ||= +'') << read(ADDR_SB).chr
    write(ADDR_SC, value & 0x7F)
    set_interrupt_requested(:serial) if interrupts_enabled_mask[:serial]
  end

  def write_wram(addr, value) = @wram[addr - WRAM_RANGE_BEGIN] = value

  def write_io_hram(addr, value, force:)
    case IO_HRAM_SUBAREAS[addr & 0xFF]
    when :input then @joypad.write(value)
    when :timer then @timer.write(addr, value, force:)
    when :io    then write_io(addr, value)
    when :hram  then @hram[addr - HRAM_RANGE_BEGIN] = value
    when :apu   then @apu.write_register(addr, value)
    when :ppu   then @ppu.write_register(addr, value)
    end
  end

  def write_io(addr, value)
    @io[addr - IO_RANGE_BEGIN] = value
    execute_dma(value) if addr == ADDR_DMA && value != 0
  end

  # DMA transfer is not supposed to be instantaneous but a good approximation
  def execute_dma(value)
    source = value << 8 # * 0x100
    (0...0xA0).each { |i| write(0xFE00 + i, read(source + i)) }
    write(ADDR_DMA, 0)
  end

  def interrupts_enabled_mask = interrupt_mask(read(ADDR_IE))
  def interrupts_requested_mask = interrupt_mask(read(ADDR_IF))

  # Equivalent bit-a-bit de (interrupts_requested_mask.values & interrupts_enabled_mask.values).any? sans alloc de Hash
  def pending_interrupts? = (read(ADDR_IE) & read(ADDR_IF)).anybits?(0x1F)

  # Contrairement à pending_interrupts?, ignore IE (utilisé pour le réveil de STOP).
  def any_interrupt_requested? = read(ADDR_IF).anybits?(0x1F)

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

  def interrupt_vector(name) = INTERRUPTS[name]

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
    require_timer_interrupt = @timer.tick!(cycles)
    set_interrupt_requested(:timer) if require_timer_interrupt
  end

  def consume_div_apu_increment = @timer.consume_div_increment
end
