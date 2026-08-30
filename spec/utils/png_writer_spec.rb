require_relative '../../lib/utils/png_writer'
require_relative '../../lib/screen'
require 'tempfile'

RSpec.describe PngWriter do
  it 'writes a valid PNG file with the correct dimensions' do
    # 2x2 image, packed RGBA pixels (see Screen.pack_color)
    white = Screen.pack_color(0xFF, 0xFF, 0xFF, 0xFF)
    black = Screen.pack_color(0x00, 0x00, 0x00, 0xFF)
    pixels = [white, black, black, white]

    Tempfile.create(['test', '.png']) do |file|
      described_class.write(file.path, pixels, width: 2, height: 2)

      bytes = File.binread(file.path)
      expect(bytes[0, 8]).to eq("\x89PNG\r\n\x1A\n".b) # PNG magic number

      width, height = bytes[16, 8].unpack('N2') # IHDR width/height, big-endian
      expect(width).to eq(2)
      expect(height).to eq(2)
    end
  end
end
