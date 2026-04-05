# GameBoy DMG-01 MMU Emulator en Ruby
class MMU
  # Adresses importantes
  ADDR_LCDC = 0xFF40
  ADDR_INP1 = 0xFF00
  # Interruptions
  ADDR_IE   = 0xFFFF
  ADDR_IF   = 0xFF0F

  # Ranges d'adresses mappées
  ROM_RANGE = 0x0000..0x7FFF
  VRAM_RANGE = 0x8000..0x9FFF
  WRAM_RANGE = 0xC000..0xDFFF
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

  class ForbiddenAccessError < StandardError; end

  def initialize(rom_bytes)
    @rom = rom_bytes
    @key_state = nil

    @vram = Array.new(0x2000, 0) # 8KB de VRAM
    @wram = Array.new(0x2000, 0) # 8KB de WRAM
    @io = Array.new(0x80, 0)     # 128 octets d'I/O
    @hram = Array.new(0x80, 0)   # 128 octets de HRAM (0xFF80..0xFFFF)

    @interrupts_enabled = false

    @inputs_selector = nil # nil, :direction, ou :button
  end

  def read_two_bytes(address)
    low, high = read(address), read(address + 1)
    (high << 8) | low
  end

  def read(addr)
    case addr
    when ROM_RANGE
      @rom[addr]
    when VRAM_RANGE
      @vram[addr - VRAM_RANGE.begin]
    when WRAM_RANGE
      @wram[addr - WRAM_RANGE.begin]
    when ADDR_INP1
      read_inputs
    when IO_RANGE
      @io[addr - IO_RANGE.begin]
    when HRAM_RANGE
      @hram[addr - HRAM_RANGE.begin]
    when ADDR_IE
      @hram[addr - HRAM_RANGE.begin]
    when ADDR_IF
      @io[addr - IO_RANGE.begin]
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

  def write(addr, value)
    case addr
    when VRAM_RANGE
      @vram[addr - VRAM_RANGE.begin] = value
    when WRAM_RANGE
      @wram[addr - WRAM_RANGE.begin] = value
    when ADDR_INP1
      if value & 0x10 == 0
        @inputs_selector = :direction
      elsif value & 0x20 == 0
        @inputs_selector = :button
      else
        @inputs_selector = nil
      end
    when IO_RANGE
      @io[addr - IO_RANGE.begin] = value
    when HRAM_RANGE
      @hram[addr - HRAM_RANGE.begin] = value
    when ADDR_IE
      @hram[addr - HRAM_RANGE.begin] = value
    when ADDR_IF
      @io[addr - IO_RANGE.begin] = value
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

  def set_key_state(key_state)
    @key_state = key_state
  end
end
