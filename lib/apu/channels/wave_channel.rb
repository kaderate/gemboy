# frozen_string_literal: true

require_relative '../period_divider'
require_relative '../length_timer'
require_relative 'channel'

class APU
  class Waveform
    LENGTH = 32

    attr_reader :current_sample

    def initialize
      @current_sample = 1 # start at 1, cf https://gbdev.io/pandocs/Audio_Registers.html#ff30ff3f--wave-pattern-ram
    end

    def advance
      @current_sample = (@current_sample + 1) % LENGTH
    end

    def reset
      @current_sample = 1
    end
  end

  # WaveChannel is a sound generator for the wave channel
  class WaveChannel < Channel
    WAVE_RAM_BYTES = Waveform::LENGTH / 2
    WAVE_RAM_START_ADDRESS = 0xFF30

    attr_reader :period_divider, :waveform, :output_level

    def initialize(channel_number:, apu:)
      super

      # Registers: the only decoded field initialized because #on_load reads it back before writing NRx3
      @initial_period_div = 0

      # Sound state
      @length_timer = LengthTimer.new(channel_number)
      @period_divider = PeriodDivider.new(channel_number)
      @waveform = Waveform.new
    end

    def tick(nb_ticks:)
      # TODO: (post-refacto): block use is not needed
      advance_waveform if @enabled && @period_divider.tick(nb_ticks) { @initial_period_div }
    end

    def on_load(addr, value)
      case addr
      when @addr_nrx0 # DAC
        @dac_enabled = value.anybits?(0x80)
        disable_channel! unless @dac_enabled

      when @addr_nrx2 # Volume
        @output_level = (value >> 5) & 0x3

      when @addr_nrx3 # Period divider
        # Set the low byte of the period divider
        @initial_period_div = (@initial_period_div & 0xFF00) | value
        @period_divider.update_next_period_div(@initial_period_div)

      when @addr_nrx4 # Length timer & Period divider
        @length_enable = value.anybits?(0x40)

        # Set the 3 high bits of the period divider
        @initial_period_div = (@initial_period_div & 0x00FF) | ((value & 0x07) << 8)
        @period_divider.update_next_period_div(@initial_period_div)
      end
    end

    def on_write(addr, value)
      case addr
      when @addr_nrx1 # Length
        @length_timer.reload(initial_length: value & 0xFF)

      when @addr_nrx4 # Control register
        channel_triggered = value.anybits?(0x80)
        trigger! if channel_triggered
        apply_length_enable_extra_clock(triggered: channel_triggered)
      end
    end

    def trigger!
      super
      @period_divider.update_current_period_div(@initial_period_div)
      @length_timer.reload_if_expired
      @waveform.reset
    end

    # See LengthTimer#apply_extra_clock_on_enable for the quirk this handles.
    def apply_length_enable_extra_clock(triggered:)
      enabled = @length_timer.apply_extra_clock_on_enable(length_enable: @length_enable)
      return if enabled.nil? || enabled || triggered

      disable_channel!
    end

    def advance_waveform = @waveform.advance

    def current_waveform_nibble
      position = @waveform.current_sample
      byte = @apu.raw(WAVE_RAM_START_ADDRESS + (position / 2))
      (byte >> (position.even? ? 4 : 0)) & 0xF
    end

    def generate_digital_sample = @output_level.zero? ? 0 : (current_waveform_nibble >> (@output_level - 1))

    def on_frame_sequencer_step(step)
      # Length timer
      enabled = @length_timer.clock(step, length_enable: @length_enable)
      return if enabled.nil?

      enabled ? enable_channel! : disable_channel!
    end
  end
end
