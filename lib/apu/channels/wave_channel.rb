# frozen_string_literal: true

require_relative '../period_divider'
require_relative '../length_timer'

class APU
  class Waveform
    WAVEFORM_LENGTH = 32
    START_ADDRESS = 0xFF30

    def initialize(mmu:)
      @current_sample = 1 # start at 1, cf https://gbdev.io/pandocs/Audio_Registers.html#ff30ff3f--wave-pattern-ram
      @mmu = mmu
    end

    def advance
      @current_sample = (@current_sample + 1) % WAVEFORM_LENGTH
    end

    def reset
      @current_sample = 1
    end

    def fetch_sample
      sample_address = START_ADDRESS + (@current_sample / 2)
      full_sample = @mmu.read(sample_address)
      sample_shift = (@current_sample % 2).zero? ? 4 : 0
      (full_sample >> sample_shift) & 0xF
    end
  end

  # WaveChannel is a sound generator for the wave channel
  class WaveChannel
    attr_reader :apu, :channel_number, :volume

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
      @period_divider = PeriodDivider.new(channel_number)
      @waveform = Waveform.new(mmu:)
    end

    def tick(nb_ticks:, registers: EMPTY_REGISTERS)
      update_state_from_registers(registers)
      return unless @enabled

      advance_waveform if @period_divider.tick(nb_ticks, fetch_period_div)
    end

    def update_state_from_registers(registers)
      return if registers.empty? # fast path

      # Period changes only take effect after the current "sample" ends (i.e. the next tick)
      @period_divider.update_next_period_div(fetch_period_div) if registers.key?(@key_nrx3) || registers.key?(@key_nrx4)
      @output_level = fetch_output_level if registers.key?(@key_nrx2)
      @length_timer.reload(initial_length: fetch_initial_length_timer) if registers.key?(@key_nrx1)

      return unless registers.key?(@key_nrx4)

      channel_triggered = registers[@key_nrx4] & 0x80 != 0
      trigger! if channel_triggered
      apply_length_enable_extra_clock(triggered: channel_triggered)
    end

    def trigger!
      @enabled = true
      @dac_enabled = fetch_dac_enabled
      @output_level = fetch_output_level
      @period_divider.update_current_period_div(fetch_period_div)
      @length_timer.reload_if_expired
      @waveform.reset
      apu.enable_master_control_channel(channel_number)
    end

    # See LengthTimer#apply_extra_clock_on_enable for the quirk this handles.
    def apply_length_enable_extra_clock(triggered:)
      enabled = @length_timer.apply_extra_clock_on_enable(length_enable: fetch_length_enable)
      return if enabled.nil?

      @enabled = enabled
      apu.disable_master_control_channel(channel_number) if !enabled && !triggered
    end

    def advance_waveform
      @waveform.advance
    end

    def generate_digital_sample
      return 0 if @output_level.zero?

      shift = @output_level - 1
      @waveform.fetch_sample >> shift
    end

    def generate_pcm_sample
      return 0 unless @enabled && @dac_enabled

      DAC.to_pcm_sample(generate_digital_sample)
    end

    def on_frame_sequencer_step(step)
      # Length timer
      enabled = @length_timer.clock(step, length_enable: fetch_length_enable)
      return if enabled.nil?

      @enabled = enabled
      apu.disable_master_control_channel(channel_number) unless enabled
    end

    def fetch_output_level = (@mmu.read(@addr_nrx2) >> 5) & 0x3
    def fetch_period_div = @mmu.read_16(@addr_nrx3) & 0x7FF
    def fetch_dac_enabled = @mmu.read(@addr_nrx0) & 0x80 != 0
    def fetch_length_enable = @mmu.read(@addr_nrx4) & 0x40 != 0
    def fetch_initial_length_timer = @mmu.read(@addr_nrx1) & 0xFF
  end
end
