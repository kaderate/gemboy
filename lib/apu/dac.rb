# frozen_string_literal: true

class APU
  # Convert a digital sample ($0-$F) to a PCM sample (-1.0..1.0)
  class DAC
    def self.to_pcm_sample(digital_sample)
      # The GB sound unit is liner, not logarithmic
      (digital_sample / 7.5) - 1.0
    end
  end
end
