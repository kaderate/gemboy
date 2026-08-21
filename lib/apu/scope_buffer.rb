# frozen_string_literal: true

class APU
  # Circular buffer of the most recent mixed samples, only allocated when the debugger asks for it.
  class ScopeBuffer
    DEFAULT_CAPACITY = 512
    CHANNEL_CAPACITY = 256

    attr_reader :capacity

    def initialize(capacity = DEFAULT_CAPACITY)
      @capacity = capacity
      @buffer = Array.new(capacity)
      @index = 0
    end

    # Kept allocation-free: samples are stored as produced and normalised at snapshot time.
    def write(sample)
      @buffer[@index] = sample
      @index = (@index + 1) % @capacity
    end

    def to_a = (@buffer[@index..] + @buffer[0...@index]).compact
  end
end
