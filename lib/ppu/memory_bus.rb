# frozen_string_literal: true

class PPU
  # The CPU's view of a Memory, through the bus: blocked (reads 0xFF, writes dropped) while the
  # PPU has locked the CPU out (see PPU#set_accessible_memory). The PPU's own internal fetch
  # bypasses this entirely by reading the wrapped Memory directly.
  class MemoryBus
    def initialize(memory)
      @memory = memory
      @accessible = true
    end

    attr_writer :accessible

    def read(addr) = @accessible ? @memory.read(addr) : 0xFF
    def write(addr, value) = @accessible && @memory.write(addr, value)
  end
end
