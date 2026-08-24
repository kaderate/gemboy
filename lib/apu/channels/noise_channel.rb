# frozen_string_literal: true

require_relative '../volume_envelope'
require_relative 'channel'

class APU
  # NoiseTimer is a sound generator for the noise channel
  class NoiseTimer
    attr_reader :period

    def initialize
      @clock_shift = 0
      @clock_divider = 0
      @period = 0
    end

    def tick(nb_ticks:)
      @period += nb_ticks

      return false unless @period >= target

      @period = 0
      true
    end

    def clock(clock_shift, clock_divider)
      @clock_shift = clock_shift
      @clock_divider = clock_divider
    end

    def target
      divider = @clock_divider.zero? ? 8 : @clock_divider * 16
      divider * (2**@clock_shift)
    end
  end

  # LFSR is a linear feedback shift register
  class LFSR
    INITIAL_WIDTH = 15

    attr_reader :value, :mode

    def initialize
      set_mode(INITIAL_WIDTH)
      reset
    end

    def tick
      bit0 = @value[0]
      bit1 = @value[1]
      @value = (@value >> 1)

      next_msb_15 = (bit0 ^ bit1) == 1 ? (1 << 14) : 0
      @value ^= next_msb_15

      return unless @mode == :short

      # Feedback bit, work on bit 6 AFTER the shift
      next_msb_7 = (bit0 ^ bit1) == 1 ? (1 << 6) : 0
      @value = (@value & ~(1 << 6)) | next_msb_7
    end

    def lsb = @value & 0x1

    # All bits set to 1 on power-up/reset
    def reset
      @value = (1 << 15) - 1
    end

    def set_mode(width)
      raise ArgumentError, 'width must be 7 or 15' unless [7, 15].include?(width)

      @mode = width == 15 ? :long : :short
    end
  end

  # NoiseChannel handles the white noise
  class NoiseChannel < Channel
    ENVELOPE_STEPS = [7].freeze

    attr_reader :volume_envelope, :noise_timer, :lfsr

    def initialize(channel_number:, apu:)
      super

      # Sound state
      @length_timer = LengthTimer.new(channel_number)
      @noise_timer = NoiseTimer.new
      @volume_envelope = VolumeEnvelope.new
      @lfsr = LFSR.new
    end

    def tick(nb_ticks:)
      return unless @enabled

      return unless @noise_timer.tick(nb_ticks:)

      @lfsr.tick
    end

    def on_load(addr, value)
      case addr
      when @addr_nrx2
        @initial_volume = value >> 4
        @envelope_sweep_pace = value & 0x07
        @increment_volume = value & 0x08 != 0

        @dac_enabled = value.anybits?(0xF8)
        disable_channel! unless @dac_enabled

      when @addr_nrx3 # Noise (CH4-specific) registers
        @initial_clock_shift = value >> 4
        @initial_clock_divider = value & 0x7
        @initial_lfsr_width = value & 0x08 == 0 ? 15 : 7
        @noise_timer.clock(@initial_clock_shift, @initial_clock_divider)
        @lfsr.set_mode(@initial_lfsr_width)

      when @addr_nrx4 # Control register
        @length_enable = value.anybits?(0x40)
      end
    end

    def on_write(addr, value)
      case addr
      when @addr_nrx1 # Length timer
        initial_length_timer = value & 0x3F
        @length_timer.reload(initial_length: initial_length_timer)

      when @addr_nrx2 # Volume envelope
        @volume_envelope.write_volume(@initial_volume)

      when @addr_nrx4 # Control register
        channel_triggered = value & 0x80 != 0
        trigger! if channel_triggered
        apply_length_enable_extra_clock(triggered: channel_triggered)
      end
    end

    def trigger!
      super
      @volume_envelope.reset(@initial_volume)
      @length_timer.reload_if_expired
      @lfsr.reset
    end

    # See LengthTimer#apply_extra_clock_on_enable for the quirk this handles.
    def apply_length_enable_extra_clock(triggered:)
      enabled = @length_timer.apply_extra_clock_on_enable(length_enable: @length_enable)
      return if enabled.nil? || enabled || triggered

      disable_channel!
    end

    def generate_digital_sample
      @volume_envelope.volume * @lfsr.lsb
    end

    def on_frame_sequencer_step(step)
      # Length timer
      enabled = @length_timer.clock(step, length_enable: @length_enable)
      unless enabled.nil?
        enabled ? enable_channel! : disable_channel!
      end

      # Envelope
      return unless ENVELOPE_STEPS.include?(step)

      @volume_envelope.tick(envelope_sweep_pace: @envelope_sweep_pace, increment_volume: @increment_volume)
    end

    def volume = @volume_envelope.volume
  end
end
