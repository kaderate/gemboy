# frozen_string_literal: true

require_relative '../volume_envelope'
require_relative 'channel'

class APU
  # NoiseTimer is a sound generator for the noise channel
  class NoiseTimer
    attr_reader :period

    def initialize(clock_shift:, clock_divider:)
      @clock_shift = clock_shift
      @clock_divider = clock_divider
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
    attr_reader :value, :mode

    def initialize(width:)
      set_mode(width)
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

    def initialize(channel_number:, apu:, mmu:)
      super

      # Sound state
      @length_timer = LengthTimer.new(channel_number)
      @noise_timer = NoiseTimer.new(clock_shift: fetch_clock_shift, clock_divider: fetch_clock_divider)
      @volume_envelope = VolumeEnvelope.new
      @lfsr = LFSR.new(width: fetch_lfsr_width)
    end

    def tick(nb_ticks:, registers: EMPTY_REGISTERS)
      update_state_from_registers(registers)
      return unless @enabled

      return unless @noise_timer.tick(nb_ticks:)

      @lfsr.tick
    end

    def update_state_from_registers(registers)
      return if registers.empty? # fast path

      # Period changes only take effect after the current "sample" ends (i.e. the next tick)
      if registers.key?(@key_nrx2)
        @volume_envelope.write_volume(fetch_volume)
        # Disable the channel if DAC is disabled
        @dac_enabled = fetch_dac_enabled
        disable_channel! unless @dac_enabled
      end

      # Length timer
      @length_timer.reload(initial_length: fetch_initial_length_timer) if registers.key?(@key_nrx1)

      # Control register
      if registers.key?(@key_nrx4)
        channel_triggered = registers[@key_nrx4] & 0x80 != 0
        trigger! if channel_triggered
        apply_length_enable_extra_clock(triggered: channel_triggered)
      end

      # Noise (CH4-specific) registers
      return unless registers.key?(@key_nrx3)

      @noise_timer.clock(fetch_clock_shift, fetch_clock_divider)
      @lfsr.set_mode(fetch_lfsr_width)
    end

    def trigger!
      super
      @volume_envelope.reset(fetch_volume)
      @length_timer.reload_if_expired
      @lfsr.reset
    end

    # See LengthTimer#apply_extra_clock_on_enable for the quirk this handles.
    def apply_length_enable_extra_clock(triggered:)
      enabled = @length_timer.apply_extra_clock_on_enable(length_enable: fetch_length_enable)
      return if enabled.nil? || enabled || triggered

      disable_channel!
    end

    def generate_digital_sample
      @volume_envelope.volume * @lfsr.lsb
    end

    def on_frame_sequencer_step(step)
      # Length timer
      enabled = @length_timer.clock(step, length_enable: fetch_length_enable)
      unless enabled.nil?
        enabled ? enable_channel! : disable_channel!
      end

      # Envelope
      return unless ENVELOPE_STEPS.include?(step)

      nrx2 = @mmu.read_io_raw(@addr_nrx2)
      envelope_sweep_pace = nrx2 & 0x07
      increment_volume = nrx2 & 0x08 != 0
      @volume_envelope.tick(envelope_sweep_pace:, increment_volume:)
    end

    def fetch_volume = @mmu.read_io_raw(@addr_nrx2) >> 4
    def fetch_dac_enabled = @mmu.read_io_raw(@addr_nrx2) & 0xf8 != 0
    def fetch_length_enable = @mmu.read_io_raw(@addr_nrx4) & 0x40 != 0
    def fetch_initial_length_timer = @mmu.read_io_raw(@addr_nrx1) & 0x3F
    def fetch_clock_shift = @mmu.read_io_raw(@addr_nrx3) >> 4
    def fetch_clock_divider = @mmu.read_io_raw(@addr_nrx3) & 0x7
    def fetch_lfsr_width = @mmu.read_io_raw(@addr_nrx3) & 0x08 == 0 ? 15 : 7
    def volume = @volume_envelope.volume
  end
end
