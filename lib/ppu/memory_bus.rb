# frozen_string_literal: true

class PPU
  # The CPU's view of a Memory through the bus: blocked while the PPU has locked the CPU out (see PPU#set_accessible_memory)
  # The PPU's own internal fetch bypasses this bus entirely by reading the wrapped Memory directly
  class MemoryBus
    attr_accessor :bank
    attr_writer :accessible

    def initialize(memory)
      @memory = memory
      @accessible = true
      @bank = 0
    end

    def read(addr) = @accessible ? @memory.read(addr, bank:) : 0xFF
    def write(addr, value) = @accessible && @memory.write(addr, value, bank:)

    def bank_byte = 0xFE | (@bank & 0x1)

    def set_bank(value)
      @bank = value & 0x1
    end
  end
end
