# frozen_string_literal: true

class APU
  # One APU register
  Register = Struct.new(:stored, :read_mask, :write_mask) do
    def read = stored | read_mask
    def write(value) = self.stored = (stored & ~write_mask) | (value & write_mask)
  end

  # The APU side of the bus: owns the bytes 0xFF10-0xFF3F
  class RegisterFile
    RANGE = (0xFF10..0xFF3F)
    BASE = RANGE.begin
    NR52 = 0xFF26

    # Bits the APU leaves undriven on a CPU read, so the bus pull-ups return them as 1
    READ_MASKS = [
      0x80, 0x3F, 0x00, 0xFF, 0xBF, # NR10-NR14
      0xFF, 0x3F, 0x00, 0xFF, 0xBF, # unused, NR21-NR24
      0x7F, 0xFF, 0x9F, 0xFF, 0xBF, # NR30-NR34
      0xFF, 0xFF, 0x00, 0x00, 0xBF, # unused, NR41-NR44
      0x00, 0x00, 0x70,             # NR50-NR52
      *([0xFF] * 9),                # unused 0xFF27-0xFF2F
      *([0x00] * 16)                # wave RAM
    ].freeze

    WRITE_MASKS = Array.new(READ_MASKS.size, 0xFF).tap { _1[NR52 - BASE] = 0x80 }.freeze

    def initialize = clear_registers!

    def clear_registers!
      @registers = READ_MASKS.each_with_index.map { |read_mask, i| Register.new(0, read_mask, WRITE_MASKS[i]) }
    end

    def read(addr) = @registers[addr - BASE].read
    def write(addr, value) = @registers[addr - BASE].write(value)

    # Raw access to the register file for the APU-side of the bus
    def raw(addr) = @registers[addr - BASE].stored

    # Power-up and off paths: set the bytes directly rather than using the bus so they reach bits a CPU write cannot
    def load(addr, value) = @registers[addr - BASE].stored = value
  end
end
