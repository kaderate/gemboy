require_relative '../../test_roms/support/png_reader'
require_relative '../../lib/utils/png_writer'
require 'tempfile'

RSpec.describe PngReader do
  let(:reference) { File.expand_path('../../test_roms/expected/dmg-acid2.png', __dir__) }

  it 'decodes a 2-bit grayscale image into one shade per pixel' do
    image = described_class.read(reference)

    expect(image.width).to eq(160)
    expect(image.height).to eq(144)
    expect(image.pixels.size).to eq(160 * 144)
    expect(image.pixels.uniq.sort).to eq([0, 1, 2, 3])
  end

  it 'undoes the scanline filters' do
    image = described_class.read(reference)

    # The reference is filtered, so a decoder ignoring filters would smear the white left border
    # of dmg-acid2 (3 = white) into arbitrary shades.
    left_border = (0...image.height).flat_map { |y| image.pixels[y * image.width, 12] }

    expect(left_border.uniq).to eq([3])
  end

  it 'rejects an image it cannot decode' do
    Tempfile.create(['truecolor', '.png']) do |file|
      PngWriter.write(file.path, [0, 1, 1, 0], width: 2, height: 2, palette: [[0, 0, 0], [255, 255, 255]])

      expect { described_class.read(file.path) }.to raise_error(PngReader::UnsupportedFormat)
    end
  end
end
