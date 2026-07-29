# frozen_string_literal: true

require_relative '../period_divider'
require_relative '../length_timer'
require_relative '../volume_envelope'

class APU
  # A channel is a sound generator
  class PulseChannel
    DUTY_PATTERNS = [
      [0, 0, 0, 0, 0, 0, 0, 1], # 12.5%
      [1, 0, 0, 0, 0, 0, 0, 1], # 25%
      [1, 0, 0, 0, 1, 1, 1, 1], # 50%
      [0, 1, 1, 1, 1, 1, 1, 0]  # 75%
    ].freeze

    ENVELOPE_STEPS = [7].freeze
    LENGTH_TIMER_STEPS = [0, 2, 4, 6].freeze
    FREQUENCY_SWEEP_STEPS = [2, 6].freeze

    attr_reader :channel_number

    def initialize(channel_number:, mmu:)
      @channel_number = channel_number
      @key_nrx0 = :"nr#{channel_number}0"
      @key_nrx1 = :"nr#{channel_number}1"
      @key_nrx2 = :"nr#{channel_number}2"
      @key_nrx3 = :"nr#{channel_number}3"
      @key_nrx4 = :"nr#{channel_number}4"
      @addr_nrx0 = REGISTERS[@key_nrx0]
      @addr_nrx1 = REGISTERS[@key_nrx1]
      @addr_nrx2 = REGISTERS[@key_nrx2]
      @addr_nrx3 = REGISTERS[@key_nrx3]
      @addr_nrx4 = REGISTERS[@key_nrx4]

      @has_sweep = channel_number == 1

      @mmu = mmu

      # Internal state
      @enabled = false
      @dac_enabled = false
      @timer = 0
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
      @volume_envelope.write_volume(fetch_volume) if registers.key?(@key_nrx2)

      channel_triggered = registers.key?(@key_nrx4) && registers[@key_nrx4] & 0x80 != 0
      return unless channel_triggered

      @enabled = true
      @dac_enabled = fetch_dac_enabled
      @period_divider.update_current_period_div(fetch_period_div)
      @length_timer.reset(initial_length: @mmu.read(@addr_nrx1) & 0x3F)
      @volume_envelope.reset(fetch_volume)
      @duty_cycle = fetch_duty_cycle
      @duty_step = 0
      @frequency_sweep_step = 0
      @shadow_frequency = fetch_frequency
    end

    def generate_digital_sample
      DUTY_PATTERNS.dig(@duty_cycle, @duty_step) * @volume_envelope.volume
    end

    def generate_pcm_sample
      return 0 unless @enabled && @dac_enabled

      DAC.to_pcm_sample(generate_digital_sample)
    end

    def on_frame_sequencer_step(step)
      # Length timer
      length_enable = @mmu.read(@addr_nrx4) & 0x40 != 0
      @enabled = @length_timer.tick(length_enable:) if LENGTH_TIMER_STEPS.include?(step) && length_enable

      # Frequency sweep (CH1 only)
      if @has_sweep && FREQUENCY_SWEEP_STEPS.include?(step)
        @frequency_sweep_step += 1
        frequency_sweep_pace = @mmu.read(@addr_nrx0) & 0x07 # TODO: read iff a sweep cycle ends or a retrigger occurs
        return if frequency_sweep_pace.zero?

        return unless @frequency_sweep_step >= frequency_sweep_pace

        @frequency_sweep_step = 0
        frequency_sweep_direction = @mmu.read(@addr_nrx1) & 0x08 == 0 ? 1 : -1
        frequency_sweep_shift = @mmu.read(@addr_nrx1) & 0x07
        @shadow_frequency += frequency_sweep_direction * @shadow_frequency / (2**frequency_sweep_shift)

        if @shadow_frequency > 0x7FF
          @enabled = false
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
    def fetch_period_div = @mmu.read_16(@addr_nrx3) & 0x7FF
    def fetch_duty_cycle = @mmu.read(@addr_nrx1) >> 6
    def fetch_dac_enabled = @mmu.read(@addr_nrx2) & 0xf8 != 0
    def fetch_frequency = @mmu.read_16(@addr_nrx3) & 0x7FF
    def volume = @volume_envelope.volume
  end
end
