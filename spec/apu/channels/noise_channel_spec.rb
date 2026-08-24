require_relative '../../../lib/apu'
require_relative '../../../lib/mmu'

RSpec.describe APU::NoiseChannel do
  let(:mmu) { build_mmu }
  let(:apu) { APU.new(mmu:, audio_queue: Queue.new) }

  # The channel state now comes from the writes the MMU dispatches, so the one under test has to
  # be the APU's own, on an MMU that knows about that APU.
  before do
    mmu.attach_apu(apu)
    mmu.write(APU::REGISTERS[:nr52], 0x80) # power on, or write_allowed? blocks everything
  end

  def trigger!(volume: 0x0F, dac_on: true, clock_shift: 0, clock_divider: 0, length_enable: false, width_mode: false)
    mmu.write(APU::REGISTERS[:nr42], dac_on ? (volume << 4) | 0x08 : 0x00)
    mmu.write(APU::REGISTERS[:nr43], (clock_shift << 4) | (width_mode ? 0x08 : 0x00) | clock_divider)
    nrx4_value = 0x80 | (length_enable ? 0x40 : 0x00)
    mmu.write(APU::REGISTERS[:nr44], nrx4_value)
  end

  describe '#tick / trigger' do
    subject(:channel) { apu.channels[4] }

    it 'is disabled and silent before any trigger' do
      expect(channel.generate_pcm_sample).to eq(0)
    end

    it 'stays silent if the DAC is off, even when triggered' do
      trigger!(dac_on: false)
      channel.tick(nb_ticks: 4)
      expect(channel.generate_pcm_sample).to eq(0)
    end

    it 'disables the channel immediately when the DAC is turned off' do
      trigger!(volume: 0x0F)
      channel.tick(nb_ticks: 4)
      mmu.write(APU::REGISTERS[:nr42], 0x00) # DAC off (volume=0, direction=decrease)
      channel.tick(nb_ticks: 4)
      expect(channel.generate_pcm_sample).to eq(0)
    end

    it 'resets the LFSR to all-1s (0x7FFF) on trigger, not 0 (0 is a fixed point that would never change)' do
      trigger!
      expect(channel.instance_variable_get(:@lfsr).instance_variable_get(:@value)).to eq(0x7FFF)
    end

    it 'loads the volume envelope from NR42 on trigger' do
      trigger!(volume: 0x0A)
      channel.tick(nb_ticks: 4)
      expect(channel.volume).to eq(0x0A)
    end

    it 'runs the LFSR in long mode by default (NR43 bit 3 clear)' do
      trigger!(width_mode: false)
      expect(channel.lfsr.mode).to eq(:long)
    end

    it 'runs the LFSR in short mode when NR43 bit 3 (width mode) is set' do
      trigger!(width_mode: true)
      expect(channel.lfsr.mode).to eq(:short)
    end

    it 'switches the LFSR mode on a mid-playback write to NR43' do
      trigger!(width_mode: false)
      channel.tick(nb_ticks: 4)

      mmu.write(APU::REGISTERS[:nr43], 0x08)
      channel.tick(nb_ticks: 4)

      expect(channel.lfsr.mode).to eq(:short)
    end
  end

  describe APU::LFSR do
    it 'initializes with all bits set to 1 (0x7FFF for the default 15-bit width)' do
      lfsr = described_class.new
      expect(lfsr.instance_variable_get(:@value)).to eq(0x7FFF)
    end

    it 'produces a non-zero, changing sequence over many ticks (regression: 0 used to be a fixed point)' do
      lfsr = described_class.new
      values = Array.new(40) do
        lfsr.tick
        lfsr.lsb
      end
      expect(values.uniq).to include(0, 1)
    end

    it '#reset restores the all-1s state after ticking' do
      lfsr = described_class.new
      10.times { lfsr.tick }
      lfsr.reset
      expect(lfsr.instance_variable_get(:@value)).to eq(0x7FFF)
    end

    # A maximal LFSR of N bits visits every state but 0, so the period is a stronger oracle
    # than any hand-written expected value: it catches a feedback bit off by one position.
    def period_of(lfsr, limit: 100_000)
      seen = {}
      limit.times do |i|
        return i - seen[lfsr.value] if seen.key?(lfsr.value)

        seen[lfsr.value] = i
        lfsr.tick
      end
      nil
    end

    it 'cycles through 2**15 - 1 states in long mode' do
      expect(period_of(described_class.new)).to eq(32_767)
    end

    it 'cycles through 2**7 - 1 states in short mode' do
      expect(period_of(described_class.new.tap { _1.set_mode(7) })).to eq(127)
    end

    it 'keeps clocking the upper bits while in short mode' do
      lfsr = described_class.new
      10.times { lfsr.tick }
      expect(lfsr.value & 0x7F).not_to be_zero # not the lock-up state, see below

      lfsr.set_mode(7)
      30.times { lfsr.tick }

      expect(lfsr.value >> 7).to be_positive
    end

    # Pandocs: switching to short mode with the bottom 7 bits already saturated locks the LFSR
    # up and silences CH4. Saturated is all-0s here, since we run the complement convention.
    it 'locks up when switched to short mode from the saturated state' do
      lfsr = described_class.new
      20.times { lfsr.tick }
      expect(lfsr.value & 0x7F).to be_zero

      lfsr.set_mode(7)
      10.times { lfsr.tick }

      expect(lfsr.value).to be_zero
    end
  end

  describe APU::NoiseTimer do
    # The timer is built in its power-up state and configured from NR43, exactly as the channel does.
    def timer(clock_shift: 0, clock_divider: 0) = described_class.new.tap { _1.clock(clock_shift, clock_divider) }

    it 'computes the period in T-cycles as divisor_table[r] << clock_shift, per hardware (NR43=0x00 -> 524288 Hz)' do
      # 4194304 Hz / 8 T-cycles = 524288 Hz, matching Pandocs' base noise clock
      expect(timer.target).to eq(8)
    end

    it 'ticks true once the accumulated cycles reach the target period' do
      noise_timer = timer(clock_divider: 1)
      expect(noise_timer.tick(nb_ticks: noise_timer.target - 1)).to eq(false)
      expect(noise_timer.tick(nb_ticks: 1)).to eq(true)
    end

    it 'treats a clock_divider of 0 as 0.5 (i.e. uses 8 instead of 0)' do
      expect(timer(clock_divider: 0).target).to eq(timer(clock_divider: 1).target / 2)
    end

    it 'doubles the period for each increment of clock_shift' do
      expect(timer(clock_shift: 1, clock_divider: 1).target).to eq(timer(clock_shift: 0, clock_divider: 1).target * 2)
    end
  end

  describe '#on_frame_sequencer_step - length timer' do
    subject(:channel) { apu.channels[4] }

    it 'does nothing when length is not enabled' do
      trigger!(length_enable: false)
      channel.tick(nb_ticks: 4)

      100.times { channel.on_frame_sequencer_step(0) }

      expect(channel.instance_variable_get(:@enabled)).to eq(true)
    end

    it 'disables the channel once the length timer reaches 0' do
      trigger!(length_enable: true)
      channel.tick(nb_ticks: 4)

      # length_timer starts at 64 - (NRx1 & 0x3F) = 64 here; step 0 is one of the clocking steps
      70.times { channel.on_frame_sequencer_step(0) }

      expect(channel.instance_variable_get(:@enabled)).to eq(false)
    end
  end

  describe '#on_frame_sequencer_step - envelope' do
    subject(:channel) { apu.channels[4] }

    it 'does not change volume when pace is 0' do
      trigger!(volume: 0x08)
      mmu.write(APU::REGISTERS[:nr42], (0x08 << 4) | 0x08) # direction=increase, pace=0
      channel.tick(nb_ticks: 4)

      10.times { channel.on_frame_sequencer_step(7) }

      expect(channel.volume).to eq(0x08)
    end

    it 'increases volume over time when direction bit is set' do
      trigger!(volume: 0x05)
      mmu.write(APU::REGISTERS[:nr42], (0x05 << 4) | 0x08 | 0x01) # direction=increase, pace=1
      channel.tick(nb_ticks: 4)

      channel.on_frame_sequencer_step(7)
      channel.on_frame_sequencer_step(7)

      expect(channel.volume).to eq(7)
    end

    it 'decreases volume over time when direction bit is clear' do
      trigger!(volume: 0x05)
      mmu.write(APU::REGISTERS[:nr42], (0x05 << 4) | 0x01) # direction=decrease, pace=1
      channel.tick(nb_ticks: 4)

      channel.on_frame_sequencer_step(7)
      channel.on_frame_sequencer_step(7)

      expect(channel.volume).to eq(3)
    end

    it 'never exceeds the maximum volume of 15' do
      trigger!(volume: 0x0F)
      mmu.write(APU::REGISTERS[:nr42], (0x0F << 4) | 0x08 | 0x01)
      channel.tick(nb_ticks: 4)

      10.times { channel.on_frame_sequencer_step(7) }

      expect(channel.volume).to eq(15)
    end
  end
end
