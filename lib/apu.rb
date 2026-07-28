# frozen_string_literal: true

require_relative 'audio_sampler'
require_relative 'cpu'

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
    @channels = [PulseChannel.new(channel_number: 1, mmu:), PulseChannel.new(channel_number: 2, mmu:)]
    @pcm_mixer = PCMMixer.new(mode: :mono)
    @audio_queue = audio_queue
    @mmu = mmu

    @debug_counter = 0
    @debug_file = File.open('apu.log', 'w')
  end

  def tick(nb_ticks)
    # handle_debug(nb_ticks)
    if @mmu.dirty_apu_registers.empty?
      channels_tick(nb_ticks:)
      channels_frame_sequencer_step
    else
      dirty_registers = @mmu.fetch_dirty_apu_registers.transform_keys { REGISTERS_INVERSE[_1] }
      process_master_control(dirty_registers)
      channels_tick(nb_ticks:, registers: dirty_registers) if @enabled
      channels_frame_sequencer_step
      @mmu.clear_dirty_apu_registers
    end

    @audio_queue << compute_pcm_sample if @enabled && update_ticks(nb_ticks)
  end

  def handle_debug(_nb_ticks)
    @debug_counter += 1
    @debug_counter = 0 if @debug_counter > 10_000
    @debug_file.puts "tick(#{nb_ticks}): vols: #{@channels.map(&:volume).join(':')}" if @debug_counter.zero?
  end

  def channels_tick(nb_ticks:, registers: EMPTY_REGISTERS)
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

  # A channel is a sound generator
  class PulseChannel
    DUTY_PATTERNS = [
      [0, 0, 0, 0, 0, 0, 0, 1], # 12.5%
      [1, 0, 0, 0, 0, 0, 0, 1], # 25%
      [1, 0, 0, 0, 1, 1, 1, 1], # 50%
      [0, 1, 1, 1, 1, 1, 1, 0]  # 75%
    ].freeze
    LENGTH_TIMER_TARGETS = [64, 64, 256, 64].freeze
    LENGTH_TIMER_STEPS = [0, 2, 4, 6].freeze
    ENVELOPE_STEPS = [7].freeze

    attr_reader :channel_number, :volume

    def initialize(channel_number:, mmu:)
      @channel_number = channel_number
      @key_nrx1 = :"nr#{channel_number}1"
      @key_nrx2 = :"nr#{channel_number}2"
      @key_nrx3 = :"nr#{channel_number}3"
      @key_nrx4 = :"nr#{channel_number}4"
      @addr_nrx1 = REGISTERS[@key_nrx1]
      @addr_nrx2 = REGISTERS[@key_nrx2]
      @addr_nrx3 = REGISTERS[@key_nrx3]
      @addr_nrx4 = REGISTERS[@key_nrx4]

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
      @dac_enabled = true # TODO: use registers
      @volume = fetch_volume
      @current_period_div = fetch_period_div
      @duty_cycle = fetch_duty_cycle
      @duty_step = 0
      @length_timer = fetch_length_timer
      @envelope_sweep_step = 0
    end

    def generate_digital_sample
      DUTY_PATTERNS.dig(@duty_cycle, @duty_step) * @volume
    end

    def generate_pcm_sample
      return 0 unless @dac_enabled

      DAC.to_pcm_sample(generate_digital_sample)
    end

    def on_frame_sequencer_step(step)
      # Length timer
      if LENGTH_TIMER_STEPS.include?(step)
        @length_timer -= 1 if @mmu.read(@addr_nrx4) & 0x40 != 0

        @enabled = false if @length_timer <= 0
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
  end

  # Convert a digital sample ($0-$F) to a PCM sample (-1.0..1.0)
  class DAC
    def self.to_pcm_sample(digital_sample)
      # The GB sound unit is liner, not logarithmic
      (digital_sample / 7.5) - 1.0
    end
  end

  # Mix all the samples together and output a PCM sample
  class PCMMixer
    HP_ALPHA = 0.999

    attr_reader :mode

    def initialize(mode:)
      raise ArgumentError, 'Mode must be :mono or :stereo' unless %i[mono stereo].include?(mode)

      @mode = mode
      @hp_capacitor = 0.0
    end

    def mix_samples(pcm_samples:)
      raise ArgumentError, 'PCM samples must be an array' unless pcm_samples.is_a?(Array) && !pcm_samples.empty?

      raw = (pcm_samples.sum / pcm_samples.size).round(2) # mean of the samples

      output = high_pass_filter(raw)

      mode == :mono ? output : [output, output]
    end

    def high_pass_filter(raw)
      output = raw - @hp_capacitor
      @hp_capacitor += output * (1.0 - HP_ALPHA)
      output
    end
  end
end
