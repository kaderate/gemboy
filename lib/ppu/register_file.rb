# frozen_string_literal: true

class PPU
  # One PPU register
  Register = Struct.new(:stored, :read_mask) do
    def read = stored | read_mask
    def write(value) = self.stored = value
  end

  # The PPU side of the bus
  class RegisterFile
    # DMA is excluded from here
    RANGE_1 = 0xFF40..0xFF45
    RANGE_2 = 0xFF47..0xFF4B
    RANGE = RANGE_1.to_a + RANGE_2.to_a
    # RANGE has a gap at DMA (0xFF46): addr - BASE alone would misindex everything from BGP
    # onward, so the compact array position is looked up explicitly per address instead.
    INDEX_BY_ADDR = RANGE.each_with_index.to_h.freeze

    READ_MASKS = [
      0x00,          # 0xFF40: LCDC
      0xFF,          # 0xFF41: STAT, TODO, not sure of the exact mask
      *([0x00] * 10) # 0xFF42..0xFF4B: the rest
    ].freeze

    def initialize = clear_registers!

    def clear_registers!
      @registers = READ_MASKS.map { |read_mask| Register.new(0, read_mask) }
    end

    def read(addr) = @registers[INDEX_BY_ADDR[addr]].read
    def write(addr, value) = @registers[INDEX_BY_ADDR[addr]].write(value)

    # Raw access to the register file for the PPU-side of the bus
    def raw(addr) = @registers[INDEX_BY_ADDR[addr]].stored

    # Power-up and off paths: set the bytes directly rather than using the bus so they reach bits a CPU write cannot
    def load(addr, value) = @registers[INDEX_BY_ADDR[addr]].stored = value
  end
end
