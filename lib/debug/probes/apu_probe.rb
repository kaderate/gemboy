# frozen_string_literal: true

require 'forwardable'
require_relative '../../apu'
require_relative 'channels/pulse_channel_probe'
require_relative 'channels/wave_channel_probe'
require_relative 'channels/noise_channel_probe'

module Debug
  module Probes
    # APUProbe exposes the state of the APU to the debugger
    class APUProbe
      extend Forwardable

      PROBE_CLASSES = {
        APU::PulseChannel => Channels::PulseChannelProbe,
        APU::WaveChannel => Channels::WaveChannelProbe,
        APU::NoiseChannel => Channels::NoiseChannelProbe
      }.freeze
      CHANNEL_KEYS = { 1 => :pulse1, 2 => :pulse2, 3 => :wave, 4 => :noise }.freeze
      MASTER_REGISTERS = %i[nr50 nr51 nr52].freeze

      def_delegators :@apu, :enabled, :mode, :channels

      def initialize(apu:, mmu:)
        @apu = apu
        @mmu = mmu
        @channel_probes = channels.to_h do |channel|
          [CHANNEL_KEYS.fetch(channel.channel_number), PROBE_CLASSES.fetch(channel.class).new(channel:)]
        end
        apu.enable_scope!
      end

      def snapshot
        registers = APU::REGISTERS.transform_values { @mmu.read_io_raw(_1) }
        { enabled:, mode:, audio_queue_size:, scope:, wave_ram:,
          master: registers.slice(*MASTER_REGISTERS), channels: channels_snapshot(registers) }
      end

      private

      def channels_snapshot(registers)
        @channel_probes.transform_values do |probe|
          probe.snapshot(registers).merge(scope: @apu.channel_scopes[probe.channel_number - 1].to_a)
        end
      end

      def wave_ram = Array.new(APU::Waveform::RAM_BYTES) { @mmu.read_io_raw(APU::Waveform::START_ADDRESS + _1) }

      # Stereo samples are mixed down here rather than on the APU hot path.
      def scope = @apu.scope_buffer.to_a.map { _1.is_a?(Array) ? (_1.sum / _1.size) : _1 }

      def audio_queue_size = @apu.audio_queue.size
    end
  end
end
