# frozen_string_literal: true

require_relative 'audio_sampler'
require_relative 'cpu'
require_relative 'apu/register_access'
require_relative 'apu/dac'
require_relative 'apu/pcm_mixer'
require_relative 'apu/scope_buffer'
require_relative 'apu/channel_factory'
require_relative 'timer'

# GameBoy Sound Unit Emulator
class APU
  include RegisterAccess

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
  attr_reader :enabled, :channels, :audio_queue, :scope_buffer, :channel_scopes, :timer

  def initialize(audio_queue:, mmu:, timer: Timer.new)
    super()
    @audio_queue = audio_queue
    @mmu = mmu
    @timer = timer

    # Internal state
    @ticks_since_last_sample = 0
    @frame_sequencer_step = 0
    @previous_enabled = false
    @enabled = false

    # For debugging
    @channel_scopes = nil
    @scope_buffer = nil

    # Internal components
    @pcm_mixer = PCMMixer.new(mode: :stereo)
    @channels = ChannelFactory.build_channels(apu: self)

    build_register_address_to_handler
    load_registers
  end

  def build_register_address_to_handler
    set_default_handler(NullAPU::DummyChannel.new)

    prefix_to_handler = @channels.to_h { |_, c| [c.register_prefix, c] }.merge('nr5' => self)
    REGISTERS.each { |key, address| set_register_address_to_handler(address:, handler: prefix_to_handler.fetch(key[0, 3])) }
  end

  def on_read(addr, read_value)
    return read_value unless addr == nr52_address

    channel_enabled_mask = @channels.map { |channel_num, channel| channel.enabled ? (1 << (channel_num - 1)) : 0 }.reduce(0, :|)
    (read_value & 0xF0) | channel_enabled_mask
  end

  def on_load(addr, value)
    return unless addr == nr52_address

    @previous_enabled = @enabled
    @enabled = value.anybits?(0x80)
  end

  def on_write(addr, _value)
    return unless addr == nr52_address

    turned_off = @previous_enabled != @enabled && !@enabled
    reset_state if turned_off
  end

  # Only NR50/51/52 route here: the channel registers have their own #write_allowed? (Channel).
  def write_allowed?(addr) = addr == nr52_address || @enabled

  def reset_state
    load(REGISTERS[:nr50], 0)
    load(REGISTERS[:nr51], 0)
    @channels.each_value(&:reset_state!)

    load_registers
  end

  def tick(nb_ticks)
    channels_tick(nb_ticks:)
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

  def channels_tick(nb_ticks:)
    return unless @enabled

    @channels.each_value { |c| c.tick(nb_ticks:) }
  end

  def channels_frame_sequencer_step
    stepped = @timer.consume_div_increment
    return unless @enabled && stepped

    @frame_sequencer_step = (@frame_sequencer_step + 1) % 8
    @channels.each_value { |c| c.on_frame_sequencer_step(@frame_sequencer_step) }
  end

  def update_ticks(nb_ticks)
    @ticks_since_last_sample += nb_ticks * AudioSampler::SOUND_SAMPLE_RATE_HZ
    if (sample_required = @ticks_since_last_sample >= CPU::T_CYCLES_PER_SECOND)
      @ticks_since_last_sample -= CPU::T_CYCLES_PER_SECOND
    end
    sample_required
  end

  def compute_pcm_sample
    panning = @registers.raw(REGISTERS[:nr51])
    master_volume = @registers.raw(REGISTERS[:nr50])

    pcm_samples = @channels.values.map(&:generate_pcm_sample)
    @channel_scopes&.each_with_index { |buffer, index| buffer.write(pcm_samples[index]) }
    @pcm_mixer.mix_samples(pcm_samples:, panning:, master_volume:)
  end

  def nr52_address = REGISTERS[:nr52]
  def mode = @pcm_mixer.mode
end
