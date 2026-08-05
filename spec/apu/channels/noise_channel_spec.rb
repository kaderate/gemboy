require_relative '../../../lib/apu'
require_relative '../../../lib/mmu'

RSpec.describe APU::NoiseChannel do
  let(:mmu) { MMU.new(Array.new(0x8000, 0x00)) }
  let(:apu) { APU.new(mmu:, audio_queue: Queue.new) }
  let(:channel_args) { { channel_number: 4, mmu:, apu: } }

  def trigger!(volume: 0x0F, dac_on: true, clock_shift: 0, clock_divider: 0, length_enable: false, width_mode: false)
    mmu.write(APU::REGISTERS[:nr42], dac_on ? (volume << 4) | 0x08 : 0x00)
    mmu.write(APU::REGISTERS[:nr43], (clock_shift << 4) | (width_mode ? 0x08 : 0x00) | clock_divider)
    nrx4_value = 0x80 | (length_enable ? 0x40 : 0x00)
    mmu.write(APU::REGISTERS[:nr44], nrx4_value)
  end

  def dirty_registers
    mmu.consume_dirty_apu_registers.transform_keys { APU::REGISTERS_INVERSE[_1] }
  end

  describe '#tick / trigger' do
    subject(:channel) { described_class.new(**channel_args) }

    it 'is disabled and silent before any trigger' do
      expect(channel.generate_pcm_sample).to eq(0)
    end

    it 'stays silent if the DAC is off, even when triggered' do
      trigger!(dac_on: false)
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      expect(channel.generate_pcm_sample).to eq(0)
    end

    it 'disables the channel immediately when the DAC is turned off' do
      trigger!(volume: 0x0F)
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      mmu.write(APU::REGISTERS[:nr42], 0x00) # DAC off (volume=0, direction=decrease)
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      expect(channel.generate_pcm_sample).to eq(0)
    end

    it 'resets the LFSR to all-1s (0x7FFF) on trigger, not 0 (0 is a fixed point that would never change)' do
      trigger!
      expect(channel.instance_variable_get(:@lfsr).instance_variable_get(:@value)).to eq(0x7FFF)
    end

    it 'loads the volume envelope from NR42 on trigger' do
      trigger!(volume: 0x0A)
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      expect(channel.volume).to eq(0x0A)
    end

    it 'uses a 15-bit-wide LFSR by default (NR43 bit 3 clear)' do
      trigger!(width_mode: false)
      expect(channel.instance_variable_get(:@lfsr).instance_variable_get(:@shift)).to eq(1 << 15)
    end

    it 'uses a 7-bit-wide LFSR when NR43 bit 3 (width mode) is set' do
      trigger!(width_mode: true)
      expect(channel.instance_variable_get(:@lfsr).instance_variable_get(:@shift)).to eq(1 << 7)
    end
  end

  describe APU::LFSR do
    it 'initializes with all bits set to 1 (0x7FFF for the default 15-bit width)' do
      lfsr = described_class.new(width: 15)
      expect(lfsr.instance_variable_get(:@value)).to eq(0x7FFF)
    end

    it 'produces a non-zero, changing sequence over many ticks (regression: 0 used to be a fixed point)' do
      lfsr = described_class.new(width: 15)
      values = Array.new(40) do
        lfsr.tick
        lfsr.lsb
      end
      expect(values.uniq).to include(0, 1)
    end

    it '#reset restores the all-1s state after ticking' do
      lfsr = described_class.new(width: 15)
      10.times { lfsr.tick }
      lfsr.reset
      expect(lfsr.instance_variable_get(:@value)).to eq(0x7FFF)
    end

    it 'raises for an out-of-range width' do
      expect { described_class.new(width: 16) }.to raise_error(ArgumentError)
    end
  end

  describe APU::NoiseTimer do
    it 'computes the period in T-cycles as divisor_table[r] << clock_shift, per hardware (NR43=0x00 -> 524288 Hz)' do
      timer = described_class.new(clock_shift: 0, clock_divider: 0)
      expect(timer.target).to eq(8) # 4194304 Hz / 8 T-cycles = 524288 Hz, matching Pandocs' base noise clock
    end

    it 'ticks true once the accumulated cycles reach the target period' do
      timer = described_class.new(clock_shift: 0, clock_divider: 1)
      expect(timer.tick(nb_ticks: timer.target - 1)).to eq(false)
      expect(timer.tick(nb_ticks: 1)).to eq(true)
    end

    it 'treats a clock_divider of 0 as 0.5 (i.e. uses 8 instead of 0)' do
      zero_divider = described_class.new(clock_shift: 0, clock_divider: 0)
      one_divider = described_class.new(clock_shift: 0, clock_divider: 1)
      expect(zero_divider.target).to eq(one_divider.target / 2)
    end

    it 'doubles the period for each increment of clock_shift' do
      timer = described_class.new(clock_shift: 0, clock_divider: 1)
      shifted = described_class.new(clock_shift: 1, clock_divider: 1)
      expect(shifted.target).to eq(timer.target * 2)
    end
  end

  describe '#on_frame_sequencer_step - length timer' do
    subject(:channel) { described_class.new(**channel_args) }

    it 'does nothing when length is not enabled' do
      trigger!(length_enable: false)
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      100.times { channel.on_frame_sequencer_step(0) }

      expect(channel.instance_variable_get(:@enabled)).to eq(true)
    end

    it 'disables the channel once the length timer reaches 0' do
      trigger!(length_enable: true)
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      # length_timer starts at 64 - (NRx1 & 0x3F) = 64 here; step 0 is one of the clocking steps
      70.times { channel.on_frame_sequencer_step(0) }

      expect(channel.instance_variable_get(:@enabled)).to eq(false)
    end
  end

  describe '#on_frame_sequencer_step - envelope' do
    subject(:channel) { described_class.new(**channel_args) }

    it 'does not change volume when pace is 0' do
      trigger!(volume: 0x08)
      mmu.write(APU::REGISTERS[:nr42], (0x08 << 4) | 0x08) # direction=increase, pace=0
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      10.times { channel.on_frame_sequencer_step(7) }

      expect(channel.volume).to eq(0x08)
    end

    it 'increases volume over time when direction bit is set' do
      trigger!(volume: 0x05)
      mmu.write(APU::REGISTERS[:nr42], (0x05 << 4) | 0x08 | 0x01) # direction=increase, pace=1
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      channel.on_frame_sequencer_step(7)
      channel.on_frame_sequencer_step(7)

      expect(channel.volume).to eq(7)
    end

    it 'decreases volume over time when direction bit is clear' do
      trigger!(volume: 0x05)
      mmu.write(APU::REGISTERS[:nr42], (0x05 << 4) | 0x01) # direction=decrease, pace=1
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      channel.on_frame_sequencer_step(7)
      channel.on_frame_sequencer_step(7)

      expect(channel.volume).to eq(3)
    end

    it 'never exceeds the maximum volume of 15' do
      trigger!(volume: 0x0F)
      mmu.write(APU::REGISTERS[:nr42], (0x0F << 4) | 0x08 | 0x01)
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      10.times { channel.on_frame_sequencer_step(7) }

      expect(channel.volume).to eq(15)
    end
  end
end
