# frozen_string_literal: true

require_relative 'channels/pulse_channel'
require_relative 'channels/wave_channel'
require_relative 'channels/noise_channel'

class APU
  # ChannelFactory is a factory for creating APU channels
  class ChannelFactory
    CHANNEL_CLASSES = {
      1 => PulseChannel,
      2 => PulseChannel,
      3 => WaveChannel,
      4 => NoiseChannel
    }.freeze

    def self.build_channels(apu:, mmu:)
      CHANNEL_CLASSES.to_h do |channel_number, channel_class|
        [channel_number, channel_class.new(channel_number:, apu:, mmu:)]
      end
    end
  end
end
