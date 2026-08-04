require_relative '../../lib/utils/png_writer'
require 'tempfile'

RSpec.describe PngWriter do
  it 'writes a valid PNG file with the correct dimensions' do
    # 2x2 image, palette index 0/1, 2-color palette
    pixels = [0, 1, 1, 0]
    palette = [[0x11, 0x22, 0x33], [0xAA, 0xBB, 0xCC]]

    Tempfile.create(['test', '.png']) do |file|
      described_class.write(file.path, pixels, width: 2, height: 2, palette:)

      bytes = File.binread(file.path)
      expect(bytes[0, 8]).to eq("\x89PNG\r\n\x1A\n".b) # PNG magic number

      width, height = bytes[16, 8].unpack('N2') # IHDR width/height, big-endian
      expect(width).to eq(2)
      expect(height).to eq(2)
    end
  end
end
