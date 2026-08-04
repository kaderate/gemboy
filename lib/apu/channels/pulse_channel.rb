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

    def initialize(channel_number:, apu:, mmu:)
      super

      # Sound state
      @length_timer = LengthTimer.new(channel_number)
      @period_divider = PeriodDivider.new(channel_number)
      @volume_envelope = VolumeEnvelope.new
      @duty_cycle = 0 # index in DUTY_PATTERNS (0..3)
      @duty_step = 0 # step in the waveform (0..7)
      @frequency_sweep_step = 0
      @shadow_frequency = 0
    end

    def tick(nb_ticks:, registers: EMPTY_REGISTERS)
      update_state_from_registers(registers)
      return unless @enabled

      @duty_step = (@duty_step + 1) % 8 if @period_divider.tick(nb_ticks, fetch_period_div)
    end

    def update_state_from_registers(registers)
      return if registers.empty? # fast path

      # Period changes only take effect after the current "sample" ends (i.e. the next tick)
      @period_divider.update_next_period_div(fetch_period_div) if registers.key?(@key_nrx3) || registers.key?(@key_nrx4)
      @duty_cycle = fetch_duty_cycle if registers.key?(@key_nrx1)
      if registers.key?(@key_nrx2)
        @volume_envelope.write_volume(fetch_volume)
        # Disable the channel if DAC is disabled
        @dac_enabled = fetch_dac_enabled
        disable_channel! unless @dac_enabled
      end
      @length_timer.reload(initial_length: fetch_initial_length_timer) if registers.key?(@key_nrx1)

      return unless registers.key?(@key_nrx4)

      channel_triggered = registers[@key_nrx4] & 0x80 != 0
      trigger! if channel_triggered
      apply_length_enable_extra_clock(triggered: channel_triggered)
    end

    def trigger!
      super
      @duty_cycle = fetch_duty_cycle
      @duty_step = 0
      @shadow_frequency = fetch_frequency
      @frequency_sweep_step = 0
      @period_divider.update_current_period_div(fetch_period_div)
      @length_timer.reload_if_expired
      @volume_envelope.reset(fetch_volume)
    end

    # See LengthTimer#apply_extra_clock_on_enable for the quirk this handles.
    def apply_length_enable_extra_clock(triggered:)
      enabled = @length_timer.apply_extra_clock_on_enable(length_enable: fetch_length_enable)
      return if enabled.nil? || enabled || triggered

      disable_channel!
    end

    def generate_digital_sample
      DUTY_PATTERNS.dig(@duty_cycle, @duty_step) * @volume_envelope.volume
    end

    def on_frame_sequencer_step(step)
      # Length timer
      enabled = @length_timer.clock(step, length_enable: fetch_length_enable)
      unless enabled.nil?
        enabled ? enable_channel! : disable_channel!
      end

      # Frequency sweep (CH1 only)
      if @has_sweep && FREQUENCY_SWEEP_STEPS.include?(step)
        @frequency_sweep_step += 1
        frequency_sweep_pace = (@mmu.read(@addr_nrx0) >> 4) & 0x07 # TODO: read iff a sweep cycle ends or a retrigger occurs
        return if frequency_sweep_pace.zero?

        return unless @frequency_sweep_step >= frequency_sweep_pace

        @frequency_sweep_step = 0
        frequency_sweep_direction = @mmu.read(@addr_nrx0) & 0x08 == 0 ? 1 : -1
        frequency_sweep_shift = @mmu.read(@addr_nrx0) & 0x07
        @shadow_frequency += frequency_sweep_direction * @shadow_frequency / (2**frequency_sweep_shift)

        if @shadow_frequency > 0x7FF
          disable_channel!
          @shadow_frequency = 0x7FF
        else
          @shadow_frequency &= 0x7FF
          # Write shadow frequency back to NRx3 and NRx4
          @mmu.write(@addr_nrx3, @shadow_frequency & 0xFF)
          @mmu.write(@addr_nrx4, (@shadow_frequency >> 8) & 0xFF)
        end
      end

      # Envelope
      return unless ENVELOPE_STEPS.include?(step)

      envelope_sweep_pace = @mmu.read(@addr_nrx2) & 0x07
      increment_volume = @mmu.read(@addr_nrx2) & 0x08 != 0
      @volume_envelope.tick(envelope_sweep_pace:, increment_volume:)
    end

    def fetch_volume = @mmu.read(@addr_nrx2) >> 4
    def fetch_dac_enabled = @mmu.read(@addr_nrx2) & 0xf8 != 0
    def fetch_period_div = @mmu.read_16(@addr_nrx3) & 0x7FF
    def fetch_duty_cycle = @mmu.read(@addr_nrx1) >> 6
    def fetch_initial_length_timer = @mmu.read(@addr_nrx1) & 0x3F
    def fetch_length_enable = @mmu.read(@addr_nrx4) & 0x40 != 0
    def fetch_frequency = @mmu.read_16(@addr_nrx3) & 0x7FF
    def volume = @volume_envelope.volume
  end
end
