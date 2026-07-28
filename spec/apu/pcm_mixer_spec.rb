require_relative '../../lib/apu/pcm_mixer'

RSpec.describe APU::PCMMixer do
  describe '#initialize' do
    it 'accepts :mono' do
      expect { described_class.new(mode: :mono) }.not_to raise_error
    end

    it 'accepts :stereo' do
      expect { described_class.new(mode: :stereo) }.not_to raise_error
    end

    it 'rejects any other mode' do
      expect { described_class.new(mode: :quad) }.to raise_error(ArgumentError)
    end
  end

  describe '#mix_samples' do
    subject(:mixer) { described_class.new(mode: :mono) }

    it 'raises on an empty sample array' do
      expect { mixer.mix_samples(pcm_samples: []) }.to raise_error(ArgumentError)
    end

    it 'raises on a non-array argument' do
      expect { mixer.mix_samples(pcm_samples: 1.0) }.to raise_error(ArgumentError)
    end

    it 'returns a single float in :mono mode' do
      result = mixer.mix_samples(pcm_samples: [1.0, -1.0])
      expect(result).to be_a(Float)
    end

    it 'returns a [left, right] pair in :stereo mode' do
      stereo_mixer = described_class.new(mode: :stereo)
      result = stereo_mixer.mix_samples(pcm_samples: [1.0])
      expect(result).to eq([result.first, result.first])
      expect(result.size).to eq(2)
    end

    it 'averages multiple channel samples' do
      # Immediately after init the high-pass capacitor is 0, so the first sample
      # passes through close to the raw average.
      result = mixer.mix_samples(pcm_samples: [1.0, -1.0])
      expect(result).to be_within(0.01).of(0.0)
    end
  end

  describe '#high_pass_filter (DC offset removal)' do
    subject(:mixer) { described_class.new(mode: :mono) }

    it 'drives a sustained constant signal towards 0 over many samples' do
      # HP_ALPHA = 0.999 => error decays as 0.999**n; need ~4600 samples to drop below 0.1
      last = nil
      6000.times { last = mixer.mix_samples(pcm_samples: [-1.0]) }
      expect(last.abs).to be < 0.1
    end

    it 'lets a fast-varying signal pass through mostly unfiltered' do
      results = []
      50.times { |i| results << mixer.mix_samples(pcm_samples: [i.even? ? 0.5 : -0.5]) }
      expect(results.last.abs).to be > 0.3
    end
  end
end
