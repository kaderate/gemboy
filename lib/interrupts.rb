# frozen_string_literal: true

# GameBoy DMG-01 interrupt controller: IE (0xFFFF), IF (0xFF0F) and IME (CPU-side master enable)
class Interrupts
  VECTORS = {
    vblank: 0x40,
    lcd_stat: 0x48,
    timer: 0x50,
    serial: 0x58,
    joypad: 0x60
  }.freeze
  NAMES = VECTORS.keys.freeze

  REGISTERS_FROM_ADDR = {
    0xFF0F => :if,
    0xFFFF => :ie
  }.freeze

  def initialize
    @ie = 0
    @if = 0
  end

  def read(addr)
    case REGISTERS_FROM_ADDR[addr]
    when :if then @if
    when :ie then @ie
    end
  end

  def write(addr, value)
    case REGISTERS_FROM_ADDR[addr]
    when :if then @if = value
    when :ie then @ie = value
    end
  end

  def request(name)
    check_name(name)
    @if |= (1 << NAMES.index(name))
  end

  def clear_requested(name)
    check_name(name)
    @if &= ~(1 << NAMES.index(name))
  end

  def enable(name)
    check_name(name)
    @ie |= (1 << NAMES.index(name))
  end

  def disable(name)
    check_name(name)
    @ie &= ~(1 << NAMES.index(name))
  end

  def enabled?(name) = enabled_mask[name]

  # Equivalent bit-a-bit de (requested_mask.values & enabled_mask.values).any? sans alloc de Hash
  def pending? = (@ie & @if).anybits?(0x1F)

  # Contrairement à pending?, ignore IE (utilisé pour le réveil de STOP).
  def any_requested? = @if.anybits?(0x1F)

  def most_important(ime)
    return nil unless ime

    active = @ie & @if
    NAMES.each_with_index { |name, i| return name if active.anybits?(1 << i) }
    nil
  end

  def vector(name) = VECTORS[name]

  def requested_mask = mask(@if)
  def enabled_mask = mask(@ie)

  private

  def mask(value)
    {
      vblank: value & 0x01 != 0,
      lcd_stat: value & 0x02 != 0,
      timer: value & 0x04 != 0,
      serial: value & 0x08 != 0,
      joypad: value & 0x10 != 0
    }
  end

  def check_name(name)
    raise "Unknown interrupt name: #{name}" unless VECTORS.key?(name)
  end
end
