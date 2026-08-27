# frozen_string_literal: true

class PPU
  class BPPDecoder
    attr_reader :pixels

    def initialize(byte1, byte2)
      @pixels = []
      (0...8).each do |x|
        bit1 = (byte1 >> (7 - x)) & 0x01
        bit2 = (byte2 >> (7 - x)) & 0x01
        color_value = (bit2 << 1) | bit1
        @pixels << color_value
      end
    end

    def [](x)
      pixels[x]
    end
  end
end
