# frozen_string_literal: true

require_relative 'channel_probe'
require_relative 'volume_envelope_probe'

module Debug
  module Probes
    module Channels
      # NoiseChannelProbe exposes the state of the noise channel to the debugger
      class NoiseChannelProbe < ChannelProbe
        def initialize(channel:)
          super
          @volume_envelope_probe = VolumeEnvelopeProbe.new(volume_envelope: channel.volume_envelope)
        end

        private

        def channel_snapshot
          { volume_envelope: @volume_envelope_probe.snapshot, lfsr:, noise_timer: }
        end

        def lfsr
          register = @channel.lfsr
          { value: register.value, width: register.width, lsb: register.lsb }
        end

        def noise_timer
          timer = @channel.noise_timer
          { period: timer.period, target: timer.target }
        end
      end
    end
  end
end
