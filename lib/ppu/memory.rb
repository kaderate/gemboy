# frozen_string_literal: true

class PPU
  # Represents a memory area. Purely a byte store -- no notion of who's allowed to touch it or
  # when (see MemoryBus for the CPU-bus accessibility gate, wrapped around this).
  class Memory
    # rubocop:disable Metrics/ParameterLists
    def initialize(size:, base_addr:, bank: 1, initial_value: 0, dirty_range: nil, empty_range: nil)
      @size = size
      @base_addr = base_addr
      @data = Array.new(size * bank, initial_value)

      # Cache management
      @dirty = false
      @dirty_range = dirty_range

      # Addresses considered empty (not accessible)
      @empty_range = empty_range
    end
    # rubocop:enable Metrics/ParameterLists

    def read(addr, length = 1, bank: 0)
      # The "empty" range (e.g. OAM's unusable 0xFEA0-0xFEFF) has no backing slot in @data
      # offset(addr) would run past the array and silently return nil instead of a byte.
      return (length == 1 ? 0xFF : Array.new(length, 0xFF)) if @empty_range&.cover?(addr & 0xFF)

      o = offset(addr, bank:)
      length == 1 ? @data[o] : @data[o, length]
    end

    def write(addr, value, bank: 0)
      return unless writable?(addr)

      @data[offset(addr, bank:)] = value

      @dirty = true if @dirty_range&.cover?(addr)
    end

    def dirty? = @dirty
    def mark_as_clean! = @dirty = false

    alias [] read
    alias []= write

    private

    def offset(addr, bank:) = (addr - @base_addr) + (bank * @size)
    def writable?(addr) = !@empty_range&.cover?(addr & 0xFF)
  end
end
