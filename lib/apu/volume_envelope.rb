# frozen_string_literal: true

class APU
  # VolumeEnvelope is a sound generator for the volume envelope channel
  class VolumeEnvelope
    attr_reader :volume, :envelope_sweep_step

    def initialize
      @envelope_sweep_step = 0
      @volume = 0
    end

    def tick(envelope_sweep_pace:, increment_volume:)
      @envelope_sweep_step += 1

      return if envelope_sweep_pace.zero?
      return unless @envelope_sweep_step >= envelope_sweep_pace

      @envelope_sweep_step = 0
      if increment_volume
        @volume += 1 if @volume < 15
      elsif @volume.positive?
        @volume -= 1
      end
    end

    def write_volume(vol)
      @volume = vol
    end

    def reset(vol)
      @envelope_sweep_step = 0
      write_volume(vol)
    end
  end
end
