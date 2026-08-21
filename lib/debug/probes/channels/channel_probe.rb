# frozen_string_literal: true

require 'forwardable'
require_relative '../../../apu'
require_relative 'length_timer_probe'

module Debug
  module Probes
    module Channels
      # ChannelProbe exposes the state shared by every channel; subclasses add their own stage
      class ChannelProbe
        extend Forwardable

        attr_reader :channel

        def_delegators :@channel, :channel_number, :enabled, :dac_enabled

        def initialize(channel:)
          @channel = channel
          @register_keys = APU::REGISTERS.keys.select { _1.start_with?("nr#{channel.channel_number}") }
          @length_timer_probe = LengthTimerProbe.new(length_timer: channel.length_timer)
        end

        def snapshot(registers)
          { enabled:, dac_enabled:, registers: registers.slice(*@register_keys),
            length_timer: @length_timer_probe.snapshot }.merge(channel_snapshot)
        end

        private

        def channel_snapshot = {}
      end
    end
  end
end
