# frozen_string_literal: true

class PPU
  # CGBPalette handles an auto-increment index register to manage the 64 bytes of the CGB palette RAM
  # Used for BCPS/BCPD and OCPS/OCPD
  class CGBPalette
    def initialize
      @bytes = Array.new(64, 0xFF) # white at power on
      @index = 0
      @auto_increment = false
      @colors = Array.new(32, 0) # precomputed RGB to packed RGBA (one per color slot)
      32.times { |color_slot| recompute_color(color_slot) }
    end

    def read_index = @index | (@auto_increment ? 0x80 : 0x00)

    def write_index(value)
      @index = value & 0x3F
      @auto_increment = value.anybits?(0x80)
    end

    def read_data = @bytes[@index]

    def write_data(value)
      @bytes[@index] = value
      recompute_color(@index / 2)

      @index = (@index + 1) & 0x3F if @auto_increment
    end

    def color(palette:, index:) = @colors[(palette * 4) + index]

    private

    def recompute_color(color_slot)
      low  = @bytes[color_slot * 2]
      high = @bytes[(color_slot * 2) + 1]
      rgb555 = low | (high << 8)

      r5 = rgb555 & 0x1F
      g5 = (rgb555 >> 5) & 0x1F
      b5 = (rgb555 >> 10) & 0x1F

      # TODO: will need color correction, cf https://gbdev.io/pandocs/Palettes.html#rgb-translation-by-cgbs
      @colors[color_slot] = Screen.pack_color((r5 << 3) | (r5 >> 2), (g5 << 3) | (g5 >> 2), (b5 << 3) | (b5 >> 2), 0xFF)
    end
  end
end
