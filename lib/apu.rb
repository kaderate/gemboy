# frozen_string_literal: true

require_relative 'audio_sampler'
require_relative 'cpu'
require_relative 'apu/dac'
require_relative 'apu/pcm_mixer'
require_relative 'apu/scope_buffer'
require_relative 'apu/channels/pulse_channel'
require_relative 'apu/channels/wave_channel'
require_relative 'apu/channels/noise_channel'

# GameBoy Sound Unit Emulator
class APU
  EMPTY_REGISTERS = {}.freeze
  REGISTERS = {
    nr10: 0xFF10, # ch1_sweep_period
    nr11: 0xFF11, # ch1_length_and_duty
    nr12: 0xFF12, # ch1_volume_envelope
    nr13: 0xFF13, # ch1_period_lsb
    nr14: 0xFF14, # ch1_period_msb_and_control
    nr21: 0xFF16, # ch2_length_and_duty
    nr22: 0xFF17, # ch2_volume_envelope
    nr23: 0xFF18, # ch2_period_lsb
    nr24: 0xFF19, # ch2_period_msb_and_control
    nr30: 0xFF1A, # ch3_dac_enable
    nr31: 0xFF1B, # ch3_length_timer
    nr32: 0xFF1C, # ch3_output_level
    nr33: 0xFF1D, # ch3_period_lsb
    nr34: 0xFF1E, # ch3_period_msb_and_control
    nr41: 0xFF20, # ch4_length_timer
    nr42: 0xFF21, # ch4_volume_envelope
    nr43: 0xFF22, # ch4_frequency_randomness
    nr44: 0xFF23, # ch4_control
    nr50: 0xFF24, # master_control
    nr51: 0xFF25, # master_panning
    nr52: 0xFF26 # master_volume
  }.freeze
  REGISTERS_INVERSE = REGISTERS.invert.freeze

  attr_reader :enabled, :mode, :channels, :audio_queue, :scope_buffer, :channel_scopes

  def initialize(audio_queue:, mmu:)
    @ticks_since_last_sample = 0
    @frame_sequencer_step = 0

    @enabled = false
    @scope_buffer = nil
    @channel_scopes = nil
    @mode = :mono
    @channels = [
      PulseChannel.new(channel_number: 1, mmu:, apu: self), PulseChannel.new(channel_number: 2, mmu:, apu: self),
      WaveChannel.new(channel_number: 3, mmu:, apu: self), NoiseChannel.new(channel_number: 4, mmu:, apu: self)
    ]
    @pcm_mixer = PCMMixer.new(mode: :stereo)
    @audio_queue = audio_queue
    @mmu = mmu
  end

  def tick(nb_ticks)
    dirty_registers = EMPTY_REGISTERS
    if @mmu.dirty_apu_registers?
      dirty_registers = @mmu.consume_dirty_apu_registers.transform_keys { REGISTERS_INVERSE[_1] }
      process_master_control(dirty_registers)
    end

    channels_tick(nb_ticks:, registers: dirty_registers)
    channels_frame_sequencer_step
    return unless @enabled && update_ticks(nb_ticks)

    sample = compute_pcm_sample
    @scope_buffer&.write(sample)
    @audio_queue << sample
  end

  def enable_scope!(capacity = ScopeBuffer::DEFAULT_CAPACITY)
    @scope_buffer = ScopeBuffer.new(capacity)
    @channel_scopes = Array.new(@channels.size) { ScopeBuffer.new(ScopeBuffer::CHANNEL_CAPACITY) }
  end

  def channels_tick(nb_ticks:, registers:)
    return unless @enabled

    @channels.each { |c| c.tick(nb_ticks:, registers:) }
  end

  def channels_frame_sequencer_step
    return unless @mmu.consume_div_apu_increment

    @frame_sequencer_step = (@frame_sequencer_step + 1) % 8
    @channels.each { |c| c.on_frame_sequencer_step(@frame_sequencer_step) }
  end

  def process_master_control(registers)
    return unless registers.key?(:nr52)

    @enabled = registers[:nr52] & 0x80 != 0
  end

  def update_ticks(nb_ticks)
    @ticks_since_last_sample += nb_ticks * AudioSampler::SOUND_SAMPLE_RATE_HZ
    if (sample_required = @ticks_since_last_sample >= CPU::T_CYCLES_PER_SECOND)
      @ticks_since_last_sample -= CPU::T_CYCLES_PER_SECOND
    end
    sample_required
  end

  def compute_pcm_sample
    panning = @mmu.read_io_raw(REGISTERS[:nr51])
    master_volume = @mmu.read_io_raw(REGISTERS[:nr50])
    pcm_samples = @channels.map(&:generate_pcm_sample)
    @channel_scopes&.each_with_index { |buffer, index| buffer.write(pcm_samples[index]) }
    @pcm_mixer.mix_samples(pcm_samples:, panning:, master_volume:)
  end

  def enable_master_control_channel(channel_number)
    nr52 = @mmu.read_io_raw(nr52_address)
    # Turn on the correct channel in NR52
    nr52 |= (1 << (channel_number - 1))
    @mmu.write(nr52_address, nr52)
  end

  def disable_master_control_channel(channel_number)
    nr52 = @mmu.read_io_raw(nr52_address)
    # Turn off the correct channel in NR52
    nr52 &= ~(1 << (channel_number - 1))
    @mmu.write(nr52_address, nr52)
  end

  def nr52_address = REGISTERS[:nr52]
end
