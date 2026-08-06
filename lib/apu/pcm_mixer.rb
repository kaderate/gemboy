# frozen_string_literal: true

class APU
  # Mix all the samples together and output a PCM sample, applying NR51 panning
  # and NR50 master volume per side (right = SO1, left = SO2).
  class PCMMixer
    HP_ALPHA = 0.999
    DEFAULT_PANNING = 0xFF # all channels routed to both sides
    DEFAULT_MASTER_VOLUME = 0x77 # max volume both sides, VIN off

    attr_reader :mode

    def initialize(mode:)
      raise ArgumentError, 'Mode must be :mono or :stereo' unless %i[mono stereo].include?(mode)

      @mode = mode
      @hp_capacitor_left = 0.0
      @hp_capacitor_right = 0.0
    end

    def mix_samples(pcm_samples:, panning: DEFAULT_PANNING, master_volume: DEFAULT_MASTER_VOLUME)
      raise ArgumentError, 'PCM samples must be an array' unless pcm_samples.is_a?(Array) && !pcm_samples.empty?

      right_volume = ((master_volume & 0x07) + 1) / 8.0
      left_volume = (((master_volume >> 4) & 0x07) + 1) / 8.0

      right = high_pass_filter(side_raw(pcm_samples, panning, 0) * right_volume, :right)
      left = high_pass_filter(side_raw(pcm_samples, panning, 4) * left_volume, :left)

      mode == :mono ? ((left + right) / 2).round(2) : [left.round(2), right.round(2)]
    end

    private

    def side_raw(pcm_samples, panning, bit_offset)
      routed_sum = pcm_samples.each_with_index.sum do |sample, i|
        panning.anybits?(1 << (bit_offset + i)) ? sample : 0
      end
      routed_sum / pcm_samples.size
    end

    def high_pass_filter(raw, side)
      capacitor = side == :left ? @hp_capacitor_left : @hp_capacitor_right
      output = raw - capacitor
      new_capacitor = capacitor + (output * (1.0 - HP_ALPHA))
      side == :left ? @hp_capacitor_left = new_capacitor : @hp_capacitor_right = new_capacitor
      output
    end
  end
end
