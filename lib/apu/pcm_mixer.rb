# frozen_string_literal: true

class APU
  # Mix all the samples together and output a PCM sample
  class PCMMixer
    HP_ALPHA = 0.999

    attr_reader :mode

    def initialize(mode:)
      raise ArgumentError, 'Mode must be :mono or :stereo' unless %i[mono stereo].include?(mode)

      @mode = mode
      @hp_capacitor = 0.0
    end

    def mix_samples(pcm_samples:)
      raise ArgumentError, 'PCM samples must be an array' unless pcm_samples.is_a?(Array) && !pcm_samples.empty?

      raw = (pcm_samples.sum / pcm_samples.size).round(2) # mean of the samples

      output = high_pass_filter(raw)

      mode == :mono ? output : [output, output]
    end

    def high_pass_filter(raw)
      output = raw - @hp_capacitor
      @hp_capacitor += output * (1.0 - HP_ALPHA)
      output
    end
  end
end
