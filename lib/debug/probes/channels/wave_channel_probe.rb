# frozen_string_literal: true

require_relative 'channel_probe'
require_relative 'period_divider_probe'

module Debug
  module Probes
    module Channels
      # WaveChannelProbe exposes the state of the wave channel to the debugger
      class WaveChannelProbe < ChannelProbe
        def_delegators :@channel, :output_level

        def initialize(channel:)
          super
          @period_divider_probe = PeriodDividerProbe.new(period_divider: channel.period_divider)
        end

        private

        # The waveform itself lives in wave RAM and is read once by APUProbe, not here.
        def channel_snapshot
          { output_level:, position: @channel.waveform.current_sample,
            period_divider: @period_divider_probe.snapshot }
        end
      end
    end
  end
end
