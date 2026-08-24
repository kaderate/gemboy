# frozen_string_literal: true

require_relative '../period_divider'
require_relative '../length_timer'
require_relative '../volume_envelope'
require_relative 'channel'

class APU
  # A channel is a sound generator
  class PulseChannel < Channel
    DUTY_PATTERNS = [
      [0, 0, 0, 0, 0, 0, 0, 1], # 12.5%
      [1, 0, 0, 0, 0, 0, 0, 1], # 25%
      [1, 0, 0, 0, 1, 1, 1, 1], # 50%
      [0, 1, 1, 1, 1, 1, 1, 0]  # 75%
    ].freeze

    ENVELOPE_STEPS = [7].freeze
    FREQUENCY_SWEEP_STEPS = [2, 6].freeze

    attr_reader :period_divider, :volume_envelope, :duty_cycle, :duty_step, :has_sweep,
                :frequency_sweep_step, :frequency_sweep_period, :frequency_sweep_enabled, :shadow_frequency

    # TODO: (post-refacto): remove ** once mmu is removed from channels
    def initialize(channel_number:, apu:, **)
      super

      # Registers: the only decoded field initialized because #on_load reads it back before writing NRx3
      @initial_period_div = 0

      # Internal state
      @duty_step = 0 # step in the waveform (0..7)
      @frequency_sweep_step = 0
      @frequency_sweep_period = 8
      @frequency_sweep_enabled = false
      @shadow_frequency = 0

      # Sound state
      @length_timer = LengthTimer.new(channel_number)
      @period_divider = PeriodDivider.new(channel_number)
      @volume_envelope = VolumeEnvelope.new
    end

    def tick(nb_ticks:, **)
      return unless @enabled

      # TODO: (post-refacto): block use is not needed
      @duty_step = (@duty_step + 1) % 8 if @period_divider.tick(nb_ticks) { @initial_period_div }
    end

    def on_load(addr, value)
      case addr
      when @addr_nrx0 # Frequency sweep
        @sweep_pace = (value >> 4) & 0x07 # raw value without the "period 0 treated as 8" quirk, cf quirked_sweep_period
        @sweep_direction = value.anybits?(0x08) ? -1 : 1 # bit 3: 0 adds to the frequency, 1 subtracts
        @sweep_shift = value & 0x07 # AKA sweep individual step in Pan Docs

      when @addr_nrx1 # Length timer
        @duty_cycle = value >> 6
        @initial_length_timer = value & 0x3F

      when @addr_nrx2 # Volume envelope
        @initial_volume = value >> 4
        @envelope_sweep_pace = value & 0x07
        @increment_volume = value.anybits?(0x08)

        @dac_enabled = value.anybits?(0xF8)
        disable_channel! unless @dac_enabled

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
      when @addr_nrx1 # Length timer
        @length_timer.reload(initial_length: @initial_length_timer)

      when @addr_nrx2 # Volume envelope
        @volume_envelope.write_volume(@initial_volume)

      when @addr_nrx4 # Control register
        channel_triggered = value.anybits?(0x80)
        trigger! if channel_triggered
        apply_length_enable_extra_clock(triggered: channel_triggered)
      end
    end

    def trigger!
      super
      @duty_step = 0
      @shadow_frequency = @initial_period_div
      @frequency_sweep_step = 0
      @period_divider.update_current_period_div(@initial_period_div)
      @length_timer.reload_if_expired
      @volume_envelope.reset(@initial_volume)

      trigger_frequency_sweep! if @has_sweep
    end

    def disable_channel_if_overflow!(new_frequency)
      return false unless new_frequency > 0x7FF

      disable_channel!
      true
    end

    # The sweep's "enabled" flag is latched only at trigger: true if pace or shift is non-zero, false otherwise
    # (both 0 means the sweep never fires until the next trigger, regardless of the "period 0 treated as 8" quirk below).
    # If shift != 0, a frequency recompute and overflow check happen immediately (new frequency not stored, just overflow check)
    def trigger_frequency_sweep!
      @frequency_sweep_period = quirked_sweep_period
      @frequency_sweep_enabled = @sweep_pace.positive? || @sweep_shift.positive?
      disable_channel_if_overflow!(compute_swept_frequency) if @sweep_shift.positive?
    end

    # See LengthTimer#apply_extra_clock_on_enable for the quirk this handles
    def apply_length_enable_extra_clock(triggered:)
      enabled = @length_timer.apply_extra_clock_on_enable(length_enable: @length_enable)
      return if enabled.nil? || enabled || triggered

      disable_channel!
    end

    def on_frame_sequencer_step(step)
      # Length timer
      enabled = @length_timer.clock(step, length_enable: @length_enable)
      unless enabled.nil?
        enabled ? enable_channel! : disable_channel!
      end

      # Frequency sweep (CH1 only)
      if @has_sweep && @frequency_sweep_enabled && FREQUENCY_SWEEP_STEPS.include?(step)
        @frequency_sweep_step += 1

        if @frequency_sweep_step >= @frequency_sweep_period
          @frequency_sweep_step = 0
          new_frequency = compute_swept_frequency
          disabled = disable_channel_if_overflow!(new_frequency)

          # Written back iff shift != 0. If shift is 0, new_frequency only used for the overflow check above
          if !disabled && @sweep_shift.positive?
            @shadow_frequency = new_frequency & 0x7FF
            @apu.load(@addr_nrx3, @shadow_frequency & 0xFF)
            @apu.load(@addr_nrx4, (@apu.raw(@addr_nrx4) & 0xF8) | ((@shadow_frequency >> 8) & 0x07))
          end

          @frequency_sweep_period = quirked_sweep_period
        end
      end

      # Envelope
      return unless ENVELOPE_STEPS.include?(step)

      @volume_envelope.tick(envelope_sweep_pace: @envelope_sweep_pace, increment_volume: @increment_volume)
    end

    def compute_swept_frequency = @shadow_frequency + (@sweep_direction * @shadow_frequency / (2**@sweep_shift))
    def generate_digital_sample = DUTY_PATTERNS.dig(@duty_cycle, @duty_step) * @volume_envelope.volume
    def quirked_sweep_period = @sweep_pace.zero? ? 8 : @sweep_pace
    def volume = @volume_envelope.volume
  end
end
