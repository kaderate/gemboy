# frozen_string_literal: true

require_relative 'channel_probe'
require_relative 'volume_envelope_probe'
require_relative 'period_divider_probe'

module Debug
  module Probes
    module Channels
      # PulseChannelProbe exposes the state of a pulse channel to the debugger
      class PulseChannelProbe < ChannelProbe
        def_delegators :@channel, :duty_cycle, :duty_step, :has_sweep, :frequency_sweep_step,
                       :frequency_sweep_period, :frequency_sweep_enabled, :shadow_frequency

        def initialize(channel:)
          super
          @volume_envelope_probe = VolumeEnvelopeProbe.new(volume_envelope: channel.volume_envelope)
          @period_divider_probe = PeriodDividerProbe.new(period_divider: channel.period_divider)
        end

        private

        def channel_snapshot
          { duty_cycle:, duty_step:, volume_envelope: @volume_envelope_probe.snapshot,
            period_divider: @period_divider_probe.snapshot, sweep: (sweep if has_sweep) }
        end

        def sweep
          { enabled: frequency_sweep_enabled, step: frequency_sweep_step,
            period: frequency_sweep_period, shadow_frequency: }
        end
      end
    end
  end
end
