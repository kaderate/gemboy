require_relative '../../lib/ppu/cgb_palette'
require_relative '../../lib/screen'

RSpec.describe PPU::CGBPalette do
  subject(:palette) { described_class.new }

  describe '#write_index / #read_index' do
    it 'auto-increments the index on data write when bit 7 of the index register is set' do
      palette.write_index(0x80) # index 0, auto-increment on
      palette.write_data(0x11)
      palette.write_data(0x22)

      expect(palette.read_index).to eq(0x82) # index advanced to 2, auto-increment bit preserved
    end

    it 'does not auto-increment when bit 7 is clear' do
      palette.write_index(0x00)
      palette.write_data(0x11)

      expect(palette.read_index).to eq(0x00)
    end

    it 'masks the index to 6 bits (0-63)' do
      palette.write_index(0xFF)
      expect(palette.read_index).to eq(0xBF) # 0x3F | 0x80
    end

    it 'wraps the index from 63 back to 0 on auto-increment' do
      palette.write_index(0xBF) # index 63, auto-increment on
      palette.write_data(0x11)

      expect(palette.read_index).to eq(0x80) # wrapped to 0
    end
  end

  describe '#write_data / #read_data' do
    it 'reads back the byte written at the current index' do
      palette.write_index(0x05)
      palette.write_data(0x42)

      expect(palette.read_data).to eq(0x42)
    end
  end

  describe '#color' do
    it 'resolves palette 0 color 1 from little-endian RGB555' do
      palette.write_index(0x82) # palette 0, color 1, low byte, auto-increment on
      palette.write_data(0x1F)  # low byte: r5=0x1F (max red), g5 low bits = 0
      palette.write_data(0x00)  # high byte: g5 high bits = 0, b5 = 0

      expect(palette.color(palette: 0, index: 1)).to eq(Screen.pack_color(0xFF, 0x00, 0x00, 0xFF))
    end

    it 'resolves palette 1 color 0 independently from palette 0' do
      palette.write_index(0x88) # palette 1, color 0, low byte, auto-increment on (8 = palette 1 * 4 colors * 2 bytes)
      palette.write_data(0x00)
      palette.write_data(0x7C) # high byte: b5 = 0x1F (max blue)

      expect(palette.color(palette: 1, index: 0)).to eq(Screen.pack_color(0x00, 0x00, 0xFF, 0xFF))
    end

    it 'defaults to opaque white-scaled-from-0xFF bytes before any write' do
      # untouched palette RAM reads as 0xFF per byte -> rgb555 = 0x7FFF -> full white
      expect(palette.color(palette: 0, index: 0)).to eq(Screen.pack_color(0xFF, 0xFF, 0xFF, 0xFF))
    end
  end
end
