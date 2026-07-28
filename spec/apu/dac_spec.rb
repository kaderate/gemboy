require_relative '../../lib/apu/dac'

RSpec.describe APU::DAC do
  describe '.to_pcm_sample' do
    it 'maps 0 to -1.0 (silence baseline)' do
      expect(described_class.to_pcm_sample(0)).to eq(-1.0)
    end

    it 'maps 15 (max digital sample) to +1.0' do
      expect(described_class.to_pcm_sample(15)).to eq(1.0)
    end

    it 'maps the midpoint linearly' do
      expect(described_class.to_pcm_sample(7.5)).to eq(0.0)
    end
  end
end
