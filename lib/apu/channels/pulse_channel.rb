# frozen_string_literal: true

class APU
  # A channel is a sound generator
  class PulseChannel
    DUTY_PATTERNS = [
      [0, 0, 0, 0, 0, 0, 0, 1], # 12.5%
      [1, 0, 0, 0, 0, 0, 0, 1], # 25%
      [1, 0, 0, 0, 1, 1, 1, 1], # 50%
      [0, 1, 1, 1, 1, 1, 1, 0]  # 75%
    ].freeze
    LENGTH_TIMER_TARGETS = [64, 64, 256, 64].freeze

    ENVELOPE_STEPS = [7].freeze
    LENGTH_TIMER_STEPS = [0, 2, 4, 6].freeze
    FREQUENCY_SWEEP_STEPS = [2, 6].freeze

    attr_reader :channel_number, :volume

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
      @length_timer_target = LENGTH_TIMER_TARGETS[channel_number - 1]

      @mmu = mmu

      # Internal state
      @enabled = false
      @dac_enabled = false
      @timer = 0
      # Sound state
      @volume = 0 # 0..15
      @current_period_div = 0 # current period in APU clock cycles, copied from NRx3-NRx4 (11-bit)
      @next_period_div = nil # next period in APU clock cycles
      @duty_cycle = 0 # index in DUTY_PATTERNS (0..3)
      @duty_step = 0 # step in the waveform (0..7)
      @length_timer = 0
      @envelope_sweep_step = 0
      @frequency_sweep_step = 0
      @shadow_frequency = 0
    end

    def tick(nb_ticks:, registers: EMPTY_REGISTERS) # rubocop:disable Metrics/MethodLength
      update_state_from_registers(registers)
      return unless @enabled

      @current_period_div += (nb_ticks / 4)

      return unless @current_period_div > 0x7FF # overflow

      # Use the next period if it's set, otherwise use the current one
      if @next_period_div
        @current_period_div = @next_period_div
        @next_period_div = nil
      else
        @current_period_div = fetch_period_div
      end

      @duty_step = (@duty_step + 1) % 8
    end

    def update_state_from_registers(registers)
      return if registers.empty? # fast path

      # Period changes only take effect after the current "sample" ends (i.e. the next tick)
      @next_period_div = fetch_period_div if registers.key?(@key_nrx3) || registers.key?(@key_nrx4)
      @duty_cycle = fetch_duty_cycle if registers.key?(@key_nrx1)
      @volume = fetch_volume if registers.key?(@key_nrx2)

      return unless registers.key?(@key_nrx4) && registers[@key_nrx4] & 0x80 != 0

      @enabled = true
      @dac_enabled = fetch_dac_enabled
      @volume = fetch_volume
      @current_period_div = fetch_period_div
      @duty_cycle = fetch_duty_cycle
      @duty_step = 0
      @length_timer = fetch_length_timer
      @envelope_sweep_step = 0
      @frequency_sweep_step = 0
      @shadow_frequency = fetch_frequency
    end

    def generate_digital_sample
      DUTY_PATTERNS.dig(@duty_cycle, @duty_step) * @volume
    end

    def generate_pcm_sample
      return 0 unless @enabled && @dac_enabled

      DAC.to_pcm_sample(generate_digital_sample)
    end

    def on_frame_sequencer_step(step)
      # Length timer
      if LENGTH_TIMER_STEPS.include?(step)
        @length_timer -= 1 if @mmu.read(@addr_nrx4) & 0x40 != 0

        @enabled = false if @length_timer <= 0
      end

      # Frequency sweep (CH1 only)
      if @has_sweep && FREQUENCY_SWEEP_STEPS.include?(step)
        @frequency_sweep_step += 1
        frequency_sweep_pace = @mmu.read(@addr_nrx0) & 0x07 # TODO: read iff a sweep cycle ends or a retrigger occurs
        return if frequency_sweep_pace.zero?

        return unless @frequency_sweep_step >= frequency_sweep_pace

        @frequency_sweep_step = 0
        frequency_sweep_direction = @mmu.read(@addr_nrx1) & 0x08 != 0 ? -1 : 1
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

      @envelope_sweep_step += 1
      envelope_sweep_pace = @mmu.read(@addr_nrx2) & 0x07
      return if envelope_sweep_pace.zero?

      return unless @envelope_sweep_step >= envelope_sweep_pace

      @envelope_sweep_step = 0
      increment_volume = @mmu.read(@addr_nrx2) & 0x08 != 0
      if increment_volume
        @volume += 1 if @volume < 15
      elsif @volume.positive?
        @volume -= 1
      end
    end

    def fetch_volume = @mmu.read(@addr_nrx2) >> 4
    def fetch_period_div = @mmu.read_16(@addr_nrx3) & 0x7FF
    def fetch_duty_cycle = @mmu.read(@addr_nrx1) >> 6
    def fetch_length_timer = @length_timer_target - (@mmu.read(@addr_nrx1) & 0x3F)
    def fetch_dac_enabled = @mmu.read(@addr_nrx2) & 0xf8 != 0
    def fetch_frequency = @mmu.read_16(@addr_nrx3) & 0x7FF
  end
end
