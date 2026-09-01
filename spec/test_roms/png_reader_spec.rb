require_relative '../../test_roms/support/png_reader'
require_relative '../../lib/utils/png_writer'
require_relative '../../lib/screen'
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

  it 'resolves a 4-bit palettized image into RGB triplets' do
    image = described_class.read(File.expand_path('../../test_roms/expected/cgb-acid2.png', __dir__))

    expect(image).to be_palettized
    expect(image.width).to eq(160)
    expect(image.height).to eq(144)
    expect(image.pixels.size).to eq(160 * 144)
    expect(image.pixels.uniq).to contain_exactly([255, 255, 255], [107, 189, 255], [0, 0, 255], [0, 0, 0],
                                                 [255, 255, 0], [173, 173, 0], [115, 115, 0], [0, 156, 0])
  end

  it 'rejects an image it cannot decode' do
    Tempfile.create(['truecolor', '.png']) do |file|
      white = Screen.pack_color(0xFF, 0xFF, 0xFF, 0xFF)
      black = Screen.pack_color(0x00, 0x00, 0x00, 0xFF)
      PngWriter.write(file.path, [black, white, white, black], width: 2, height: 2)

      expect { described_class.read(file.path) }.to raise_error(PngReader::UnsupportedFormat)
    end
  end
end
