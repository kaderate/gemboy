require_relative '../../test_roms/support/rom_test_runner'

RSpec.describe RomTestRunner do
  let(:reference) { File.expand_path('../../test_roms/expected/dmg-acid2.png', __dir__) }
  let(:expected_pixels) { PngReader.read(reference).pixels.map { |shade| 3 - shade } }

  describe '.count_mismatches' do
    it 'counts no difference against a framebuffer matching the reference' do
      expect(described_class.count_mismatches(expected_pixels, reference)).to eq(0)
    end

    it 'counts every differing pixel' do
      pixels = expected_pixels.dup
      [0, 1000, 23_039].each { |i| pixels[i] = (pixels[i] + 1) % 4 }

      expect(described_class.count_mismatches(pixels, reference)).to eq(3)
    end

    it 'rejects a reference of a different size' do
      expect { described_class.count_mismatches(expected_pixels.first(10), reference) }
        .to raise_error(ArgumentError, /expected 10 pixels/)
    end
  end

  describe '.status_for' do
    it 'grades a mismatch-free comparison as passed, even when the ROM never stopped on its own' do
      expect(described_class.status_for('', true, 0)).to eq(:passed)
    end

    it 'grades any difference as failed' do
      expect(described_class.status_for('', true, 1)).to eq(:failed)
    end

    it 'keeps reporting a timeout when no reference is given' do
      expect(described_class.status_for('', true, nil)).to eq(:timeout)
    end
  end
end
