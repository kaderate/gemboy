require_relative '../../../lib/apu'
require_relative '../../../lib/mmu'

RSpec.describe APU::PulseChannel do
  let(:mmu) { MMU.new(Array.new(0x8000, 0x00)) }

  def trigger!(channel_number:, duty: 0b10, volume: 0x0F, dac_on: true, period: 0x400, length_enable: false)
    nrx1 = APU::REGISTERS[:"nr#{channel_number}1"]
    nrx2 = APU::REGISTERS[:"nr#{channel_number}2"]
    nrx3 = APU::REGISTERS[:"nr#{channel_number}3"]
    nrx4 = APU::REGISTERS[:"nr#{channel_number}4"]

    mmu.write(nrx1, duty << 6)
    mmu.write(nrx2, dac_on ? (volume << 4) | 0x08 : 0x00)
    mmu.write(nrx3, period & 0xFF)
    nrx4_value = 0x80 | (length_enable ? 0x40 : 0x00) | ((period >> 8) & 0x07)
    mmu.write(nrx4, nrx4_value)
  end

  def dirty_registers
    mmu.consume_dirty_apu_registers.transform_keys { APU::REGISTERS_INVERSE[_1] }
  end

  describe '#tick / trigger' do
    subject(:channel) { described_class.new(channel_number: 2, mmu:) }

    it 'is disabled and silent before any trigger' do
      expect(channel.generate_pcm_sample).to eq(0)
    end

    it 'becomes enabled and produces sound after a trigger' do
      trigger!(channel_number: 2, volume: 0x0F)
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      expect(channel.volume).to eq(0x0F)
      expect(channel.generate_pcm_sample).not_to eq(0)
    end

    it 'stays silent if the DAC is off, even when triggered' do
      trigger!(channel_number: 2, dac_on: false)
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      expect(channel.generate_pcm_sample).to eq(0)
    end

    it 'keeps a stable pitch across many overflow cycles (regression: nil vs 0 sentinel)' do
      trigger!(channel_number: 2, period: 0x400) # ~ half of 0x7FF, overflows every (0x7FF-0x400+1)*4 T-cycles
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      period_before = channel.instance_variable_get(:@current_period_div)

      # Advance well past a full overflow cycle without touching any register again.
      50.times { channel.tick(nb_ticks: 16, registers: APU::EMPTY_REGISTERS) }

      # The period divider must keep cycling near the configured period, never collapse to 0.
      expect(channel.instance_variable_get(:@current_period_div)).to be >= 0
      expect(period_before).to be > 0
    end
  end

  describe '#on_frame_sequencer_step - length timer' do
    subject(:channel) { described_class.new(channel_number: 2, mmu:) }

    it 'does nothing when length is not enabled' do
      trigger!(channel_number: 2, length_enable: false)
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      100.times { channel.on_frame_sequencer_step(0) }

      expect(channel.generate_pcm_sample).not_to eq(0)
    end

    it 'disables the channel once the length timer reaches 0' do
      trigger!(channel_number: 2, length_enable: true)
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      # length_timer starts at 64 - (NRx1 & 0x3F) = 64 here; step 0 is one of the clocking steps
      70.times { channel.on_frame_sequencer_step(0) }

      expect(channel.generate_pcm_sample).to eq(0)
    end
  end

  describe '#on_frame_sequencer_step - envelope' do
    subject(:channel) { described_class.new(channel_number: 2, mmu:) }

    it 'does not change volume when pace is 0' do
      nrx2 = APU::REGISTERS[:nr22]
      trigger!(channel_number: 2, volume: 0x08)
      mmu.write(nrx2, (0x08 << 4) | 0x08) # direction=increase, pace=0
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      10.times { channel.on_frame_sequencer_step(7) }

      expect(channel.volume).to eq(0x08)
    end

    it 'increases volume over time when direction bit is set' do
      nrx2 = APU::REGISTERS[:nr22]
      trigger!(channel_number: 2, volume: 0x05)
      mmu.write(nrx2, (0x05 << 4) | 0x08 | 0x01) # direction=increase, pace=1
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      channel.on_frame_sequencer_step(7)
      channel.on_frame_sequencer_step(7)

      expect(channel.volume).to eq(7) # pace=1 triggers on every envelope step (7), no waiting needed
    end

    it 'decreases volume over time when direction bit is clear' do
      nrx2 = APU::REGISTERS[:nr22]
      trigger!(channel_number: 2, volume: 0x05)
      mmu.write(nrx2, (0x05 << 4) | 0x01) # direction=decrease, pace=1
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      channel.on_frame_sequencer_step(7)
      channel.on_frame_sequencer_step(7)

      expect(channel.volume).to eq(3) # pace=1 triggers on every envelope step (7), no waiting needed
    end

    it 'never exceeds the maximum volume of 15' do
      nrx2 = APU::REGISTERS[:nr22]
      trigger!(channel_number: 2, volume: 0x0F)
      mmu.write(nrx2, (0x0F << 4) | 0x08 | 0x01)
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      10.times { channel.on_frame_sequencer_step(7) }

      expect(channel.volume).to eq(15)
    end
  end

  describe '#on_frame_sequencer_step - frequency sweep' do
    it 'applies to channel 1' do
      channel = described_class.new(channel_number: 1, mmu:)
      nrx0 = APU::REGISTERS[:nr10]
      nrx1 = APU::REGISTERS[:nr11]
      mmu.write(nrx0, 0x01) # pace=1, shift=0... need shift too
      mmu.write(nrx0, (0x01 << 4) | 0x01) # pace=1, direction=increase(bit3=0 means increase per impl), shift=1
      trigger!(channel_number: 1, period: 0x400)
      mmu.write(nrx1, 0x01) # shift=1 lives in NRx1 per this implementation
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      expect { channel.on_frame_sequencer_step(2) }.not_to raise_error
    end

    it 'does not corrupt channel 2 registers (regression: sweep must be CH1-only)' do
      channel2 = described_class.new(channel_number: 2, mmu:)
      trigger!(channel_number: 2, duty: 0b10, volume: 0x0F, period: 0x400)
      channel2.tick(nb_ticks: 4, registers: dirty_registers)

      volume_before = channel2.volume
      duty_before = channel2.instance_variable_get(:@duty_cycle)

      50.times { channel2.on_frame_sequencer_step(2) } # sweep-only step
      50.times { channel2.on_frame_sequencer_step(6) }

      # Sweep must never touch CH2's own volume/duty (it has no NR20 register).
      expect(channel2.volume).to eq(volume_before)
      expect(channel2.instance_variable_get(:@duty_cycle)).to eq(duty_before)
    end
  end
end
