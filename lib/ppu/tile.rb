# frozen_string_literal: true

class PPU
  class Tile
    attr_accessor :lines

    def initialize(data:)
      @lines = initialize_lines(data)
    end

    def pixel_color(x, y)
      lines[y][x]
    end

    private

    def initialize_lines(data)
      res = []
      data.each_slice(2) do |byte1, byte2|
        # Decoder les 2 bytes pour obtenir les couleurs des 8 pixels de la ligne
        res << BPPDecoder.new(byte1, byte2)
      end
      res
    end
  end
end
