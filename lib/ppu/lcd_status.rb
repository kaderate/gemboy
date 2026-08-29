# frozen_string_literal: true

class PPU
  class LcdStatus
    STORED_FIELDS_MASK = 0x78 # Sum of all except mode and lyc_equals_ly

    def initialize(bytes:, ppu:, mode_obj:)
      @bytes = bytes
      @ppu = ppu
      @mode_obj = mode_obj
    end

    def lyc_interrupt_enable = bytes.anybits?(0x40)
    def mode_2_interrupt_enable = bytes.anybits?(0x20)
    def mode_1_interrupt_enable = bytes.anybits?(0x10)
    def mode_0_interrupt_enable = bytes.anybits?(0x08)
    def lyc_equals_ly = @ppu.ly == @ppu.registers.raw(REGISTERS[:lyc])
    def mode = @mode_obj.mode_index

    def bytes = (@bytes & STORED_FIELDS_MASK) | ((mode || 0) & 0x03) | (lyc_equals_ly ? 0x04 : 0x00)

    def bytes=(value)
      @bytes = value & STORED_FIELDS_MASK
    end
  end
end
