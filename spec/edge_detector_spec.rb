# frozen_string_literal: true

require_relative '../lib/edge_detector'

RSpec.describe EdgeDetector do
  subject(:edge_detector) { described_class.new }

  describe '#rising?' do
    it 'is false while the signal stays low' do
      expect(edge_detector.rising?(false)).to eq(false)
      expect(edge_detector.rising?(false)).to eq(false)
    end

    it 'is true on the low-to-high transition' do
      edge_detector.rising?(false)
      expect(edge_detector.rising?(true)).to eq(true)
    end

    it 'is false while the signal stays high, after the initial rise' do
      edge_detector.rising?(true)
      expect(edge_detector.rising?(true)).to eq(false)
    end

    it 'is false on the high-to-low transition' do
      edge_detector.rising?(true)
      expect(edge_detector.rising?(false)).to eq(false)
    end
  end

  describe '#falling?' do
    it 'is false while the signal stays high' do
      edge_detector.falling?(true)
      expect(edge_detector.falling?(true)).to eq(false)
    end

    it 'is true on the high-to-low transition' do
      edge_detector.falling?(true)
      expect(edge_detector.falling?(false)).to eq(true)
    end

    it 'is false while the signal stays low, after the initial fall' do
      edge_detector.falling?(false)
      expect(edge_detector.falling?(false)).to eq(false)
    end

    it 'is false on the low-to-high transition' do
      edge_detector.falling?(false)
      expect(edge_detector.falling?(true)).to eq(false)
    end
  end

  it 'starts low, so the first #rising?(true) call fires immediately' do
    expect(edge_detector.rising?(true)).to eq(true)
  end
end
