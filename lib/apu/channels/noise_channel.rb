# frozen_string_literal: true

require_relative '../volume_envelope'

class APU
  # NoiseTimer is a sound generator for the noise channel
  class NoiseTimer
    # Ratio between the CPU clock (4194304 Hz) and the noise channel's base clock (524288 Hz)
    CPU_TO_NOISE_CLOCK_RATIO = 8

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

    def target
      divider = @clock_divider.zero? ? 8 : @clock_divider * 16
      CPU_TO_NOISE_CLOCK_RATIO * divider * (2**@clock_shift)
    end
  end

  # LFSR is a linear feedback shift register
  class LFSR
    def initialize(width:)
      raise ArgumentError, 'width must be between 0 and 15' unless width.between?(0, 15)

      @shift = 1 << width
      @value = 0
    end

    def tick
      bit0 = @value[0]
      bit1 = @value[1]
      next_msb = (bit0 ^ bit1) == 1 ? @shift : 0
      @value = (@value >> 1) ^ next_msb
    end

    def lsb
      @value & 0x1
    end

    def reset
      @value = 0
    end
  end

  # NoiseChannel handles the white noise
  class NoiseChannel
    ENVELOPE_STEPS = [7].freeze
    LENGTH_TIMER_STEPS = [0, 2, 4, 6].freeze

    attr_reader :apu, :channel_number

    def initialize(channel_number:, apu:, mmu:)
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

      @apu = apu
      @mmu = mmu

      # Internal state
      @enabled = false
      @dac_enabled = false
      @timer = 0
      # Sound state
      @length_timer = LengthTimer.new(channel_number)
      @noise_timer = NoiseTimer.new(clock_shift: fetch_clock_shift, clock_divider: fetch_clock_divider)
      @volume_envelope = VolumeEnvelope.new
      @lfsr = LFSR.new(width: 15)
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
      @volume_envelope.write_volume(fetch_volume) if registers.key?(@key_nrx2)

      reload_length_timer(force: true) if registers.key?(@key_nrx1)

      channel_triggered = registers.key?(@key_nrx4) && registers[@key_nrx4] & 0x80 != 0
      return unless channel_triggered

      @enabled = true
      @dac_enabled = fetch_dac_enabled
      @volume_envelope.reset(fetch_volume)
      reload_length_timer
      @lfsr.reset
      apu.enable_master_control_channel(channel_number)
    end

    def reload_length_timer(force: false)
      @length_timer.reset(initial_length: fetch_initial_length_timer, force:)
    end

    def generate_digital_sample
      @volume_envelope.volume * @lfsr.lsb
    end

    def generate_pcm_sample
      return 0 unless @enabled && @dac_enabled

      DAC.to_pcm_sample(generate_digital_sample)
    end

    def on_frame_sequencer_step(step)
      # Length timer
      length_enable = fetch_length_enable
      if LENGTH_TIMER_STEPS.include?(step) && length_enable
        @enabled = @length_timer.tick(length_enable:)
        apu.disable_master_control_channel(channel_number) unless @enabled
      end

      # Envelope
      return unless ENVELOPE_STEPS.include?(step)

      envelope_sweep_pace = @mmu.read(@addr_nrx2) & 0x07
      increment_volume = @mmu.read(@addr_nrx2) & 0x08 != 0
      @volume_envelope.tick(envelope_sweep_pace:, increment_volume:)
    end

    def fetch_volume = @mmu.read(@addr_nrx2) >> 4
    def fetch_dac_enabled = @mmu.read(@addr_nrx2) & 0xf8 != 0
    def fetch_length_enable = @mmu.read(@addr_nrx4) & 0x40 != 0
    def fetch_initial_length_timer = @mmu.read(@addr_nrx1) & 0x3F
    def fetch_clock_shift = @mmu.read(@addr_nrx3) >> 4
    def fetch_clock_divider = @mmu.read(@addr_nrx3) & 0x7
    def volume = @volume_envelope.volume
  end
end
