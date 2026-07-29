# frozen_string_literal: true

require_relative 'audio_sampler'
require_relative 'cpu'
require_relative 'apu/dac'
require_relative 'apu/pcm_mixer'
require_relative 'apu/channels/pulse_channel'
require_relative 'apu/channels/wave_channel'

# GameBoy Sound Unit Emulator
class APU
  T_CYCLES_PER_SAMPLE = (CPU::T_CYCLES_PER_SECOND / AudioSampler::SOUND_SAMPLE_RATE_HZ).to_i
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
    nr52: 0xFF26, # master_volume

    wave_pattern0: 0xFF30,
    wave_pattern1: 0xFF31,
    wave_pattern2: 0xFF32,
    wave_pattern3: 0xFF33,
    wave_pattern4: 0xFF34,
    wave_pattern5: 0xFF35,
    wave_pattern6: 0xFF36,
    wave_pattern7: 0xFF37,
    wave_pattern8: 0xFF38,
    wave_pattern9: 0xFF39,
    wave_pattern10: 0xFF3A,
    wave_pattern11: 0xFF3B,
    wave_pattern12: 0xFF3C,
    wave_pattern13: 0xFF3D,
    wave_pattern14: 0xFF3E,
    wave_pattern15: 0xFF3F
  }.freeze
  REGISTERS_INVERSE = REGISTERS.invert.freeze

  attr_reader :mode

  def initialize(audio_queue:, mmu:)
    @ticks_since_last_sample = 0
    @frame_sequencer_step = 0

    @enabled = false
    @mode = :mono
    @channels = [PulseChannel.new(channel_number: 1, mmu:), PulseChannel.new(channel_number: 2, mmu:),
                 WaveChannel.new(channel_number: 3, mmu:)]
    @pcm_mixer = PCMMixer.new(mode: :mono)
    @audio_queue = audio_queue
    @mmu = mmu
  end

  def tick(nb_ticks)
    dirty_registers = EMPTY_REGISTERS
    unless @mmu.dirty_apu_registers.empty?
      dirty_registers = @mmu.consume_dirty_apu_registers.transform_keys { REGISTERS_INVERSE[_1] }
      process_master_control(dirty_registers)
    end

    channels_tick(nb_ticks:, registers: dirty_registers)
    channels_frame_sequencer_step
    @audio_queue << compute_pcm_sample if @enabled && update_ticks(nb_ticks)
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
    @ticks_since_last_sample += nb_ticks
    sample_required = @ticks_since_last_sample >= T_CYCLES_PER_SAMPLE
    @ticks_since_last_sample %= T_CYCLES_PER_SAMPLE
    sample_required
  end

  def compute_pcm_sample
    @pcm_mixer.mix_samples(pcm_samples: @channels.map(&:generate_pcm_sample))
  end
end
