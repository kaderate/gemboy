# frozen_string_literal: true

require_relative 'audio_sampler'
require_relative 'cpu'
require_relative 'apu/register_access'
require_relative 'apu/dac'
require_relative 'apu/pcm_mixer'
require_relative 'apu/scope_buffer'
require_relative 'apu/channel_factory'

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

  attr_reader :enabled, :mode, :channels, :audio_queue, :scope_buffer, :channel_scopes

  def initialize(audio_queue:, mmu:)
    super()
    @audio_queue = audio_queue
    @mmu = mmu

    @ticks_since_last_sample = 0
    @frame_sequencer_step = 0

    @enabled = false
    @scope_buffer = nil
    @channel_scopes = nil
    @mode = :mono

    @channels = ChannelFactory.build_channels(apu: self)
    build_register_address_to_handler
    load_registers
    @pcm_mixer = PCMMixer.new(mode: :stereo)
  end

  def load_registers
    RegisterFile::RANGE.each { |addr| handler_for_addr(addr).on_load(addr, @registers.raw(addr)) }
  end

  def build_register_address_to_handler
    prefix_to_channel = { nr1: 1, nr2: 2, nr3: 3, nr4: 4, nr5: :master }
    default_handler = NullAPU::DummyChannel.new

    @register_address_to_handler = REGISTERS.each_with_object(Hash.new(default_handler)) do |(key, address), hash|
      channel_number = prefix_to_channel.fetch(key[0, 3].to_sym)
      hash[address] = channel_number == :master ? self : @channels[channel_number]
    end
  end

  def on_load(addr, value)
    # TODO: handle master (NR52)
  end

  def on_write(addr, value)
    # TODO: handle the rest of the master registers
    @enabled = value.anybits?(0x80) if addr == nr52_address
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
    return unless @mmu.consume_div_apu_increment

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

  def enable_master_control_channel(channel_number)
    nr52 = @registers.raw(nr52_address)
    # Turn on the correct channel in NR52
    nr52 |= (1 << (channel_number - 1))
    load(nr52_address, nr52)
  end

  def disable_master_control_channel(channel_number)
    nr52 = @registers.raw(nr52_address)
    # Turn off the correct channel in NR52
    nr52 &= ~(1 << (channel_number - 1))
    load(nr52_address, nr52)
  end

  def nr52_address = REGISTERS[:nr52]

  def handler_for_addr(addr) = @register_address_to_handler[addr]
end
