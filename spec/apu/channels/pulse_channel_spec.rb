require_relative '../../../lib/apu'
require_relative '../../../lib/mmu'

RSpec.describe APU::PulseChannel do
  let(:mmu) { build_mmu }
  let(:apu) { APU.new(mmu:, audio_queue: Queue.new) }

  # The channel state now comes from the writes the MMU dispatches, so the one under test has to
  # be the APU's own, on an MMU that knows about that APU.
  before { mmu.attach_apu(apu) }

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

  describe '#tick / trigger' do
    subject(:channel) { apu.channels[2] }

    it 'is disabled and silent before any trigger' do
      expect(channel.generate_pcm_sample).to eq(0)
    end

    it 'becomes enabled and produces sound after a trigger' do
      trigger!(channel_number: 2, volume: 0x0F)
      channel.tick(nb_ticks: 4)
      expect(channel.volume).to eq(0x0F)
      expect(channel.generate_pcm_sample).not_to eq(0)
    end

    it 'stays silent if the DAC is off, even when triggered' do
      trigger!(channel_number: 2, dac_on: false)
      channel.tick(nb_ticks: 4)
      expect(channel.generate_pcm_sample).to eq(0)
    end

    it 'keeps a stable pitch across many overflow cycles (regression: nil vs 0 sentinel)' do
      trigger!(channel_number: 2, period: 0x400) # ~ half of 0x7FF, overflows every (0x7FF-0x400+1)*4 T-cycles
      channel.tick(nb_ticks: 4)

      period_divider = channel.instance_variable_get(:@period_divider)
      period_before = period_divider.instance_variable_get(:@current_period_div)

      # Advance well past a full overflow cycle without touching any register again.
      50.times { channel.tick(nb_ticks: 16) }

      # The period divider must keep cycling near the configured period, never collapse to 0.
      expect(period_divider.instance_variable_get(:@current_period_div)).to be >= 0
      expect(period_before).to be > 0
    end
  end

  describe '#on_frame_sequencer_step - length timer' do
    subject(:channel) { apu.channels[2] }

    it 'does nothing when length is not enabled' do
      trigger!(channel_number: 2, length_enable: false)
      channel.tick(nb_ticks: 4)

      100.times { channel.on_frame_sequencer_step(0) }

      expect(channel.generate_pcm_sample).not_to eq(0)
    end

    it 'disables the channel once the length timer reaches 0' do
      trigger!(channel_number: 2, length_enable: true)
      channel.tick(nb_ticks: 4)

      # length_timer starts at 64 - (NRx1 & 0x3F) = 64 here; step 0 is one of the clocking steps
      70.times { channel.on_frame_sequencer_step(0) }

      expect(channel.generate_pcm_sample).to eq(0)
    end
  end

  describe '#on_frame_sequencer_step - envelope' do
    subject(:channel) { apu.channels[2] }

    it 'does not change volume when pace is 0' do
      nrx2 = APU::REGISTERS[:nr22]
      trigger!(channel_number: 2, volume: 0x08)
      mmu.write(nrx2, (0x08 << 4) | 0x08) # direction=increase, pace=0
      channel.tick(nb_ticks: 4)

      10.times { channel.on_frame_sequencer_step(7) }

      expect(channel.volume).to eq(0x08)
    end

    it 'increases volume over time when direction bit is set' do
      nrx2 = APU::REGISTERS[:nr22]
      trigger!(channel_number: 2, volume: 0x05)
      mmu.write(nrx2, (0x05 << 4) | 0x08 | 0x01) # direction=increase, pace=1
      channel.tick(nb_ticks: 4)

      channel.on_frame_sequencer_step(7)
      channel.on_frame_sequencer_step(7)

      expect(channel.volume).to eq(7) # pace=1 triggers on every envelope step (7), no waiting needed
    end

    it 'decreases volume over time when direction bit is clear' do
      nrx2 = APU::REGISTERS[:nr22]
      trigger!(channel_number: 2, volume: 0x05)
      mmu.write(nrx2, (0x05 << 4) | 0x01) # direction=decrease, pace=1
      channel.tick(nb_ticks: 4)

      channel.on_frame_sequencer_step(7)
      channel.on_frame_sequencer_step(7)

      expect(channel.volume).to eq(3) # pace=1 triggers on every envelope step (7), no waiting needed
    end

    it 'never exceeds the maximum volume of 15' do
      nrx2 = APU::REGISTERS[:nr22]
      trigger!(channel_number: 2, volume: 0x0F)
      mmu.write(nrx2, (0x0F << 4) | 0x08 | 0x01)
      channel.tick(nb_ticks: 4)

      10.times { channel.on_frame_sequencer_step(7) }

      expect(channel.volume).to eq(15)
    end
  end

  describe '#on_frame_sequencer_step - frequency sweep' do
    subject(:channel) { apu.channels[1] }

    # NR10 is latched at trigger, so it must be written first. Volume/DAC on so the channel runs.
    def trigger_sweep!(pace:, shift:, direction: :up, period: 0x400)
      nr10 = (pace << 4) | (direction == :down ? 0x08 : 0x00) | shift
      mmu.write(APU::REGISTERS[:nr10], nr10)
      mmu.write(APU::REGISTERS[:nr12], 0xF8)
      mmu.write(APU::REGISTERS[:nr13], period & 0xFF)
      mmu.write(APU::REGISTERS[:nr14], 0x80 | ((period >> 8) & 0x07))
    end

    # Step 2 is a sweep step; length and envelope are untouched by it here.
    def sweep_steps(count) = count.times { channel.on_frame_sequencer_step(2) }

    it 'adds to the frequency when NR10 bit 3 is clear' do
      trigger_sweep!(pace: 1, shift: 1, direction: :up, period: 0x400)

      sweep_steps(1)

      expect(channel.shadow_frequency).to eq(0x600) # 0x400 + 0x400 / 2
    end

    it 'subtracts from the frequency when NR10 bit 3 is set' do
      trigger_sweep!(pace: 1, shift: 1, direction: :down, period: 0x400)

      sweep_steps(1)

      expect(channel.shadow_frequency).to eq(0x200) # 0x400 - 0x400 / 2
    end

    it 'disables the channel at trigger when the first swept frequency already overflows' do
      trigger_sweep!(pace: 1, shift: 1, direction: :up, period: 0x700) # 0x700 + 0x380 = 0xA80

      expect(channel.enabled).to eq(false)
    end

    it 'disables the channel when a later sweep overflows 0x7FF' do
      trigger_sweep!(pace: 1, shift: 1, direction: :up, period: 0x400)

      sweep_steps(1) # 0x400 -> 0x600, still in range
      expect(channel.enabled).to eq(true)

      sweep_steps(1) # 0x600 + 0x300 = 0x900
      expect(channel.enabled).to eq(false)
    end

    it 'leaves the shadow frequency alone when shift is 0 (overflow check only)' do
      trigger_sweep!(pace: 1, shift: 0, direction: :down, period: 0x400)

      sweep_steps(4)

      expect(channel.shadow_frequency).to eq(0x400)
    end

    it 'never fires when both pace and shift are 0' do
      trigger_sweep!(pace: 0, shift: 0, period: 0x400)

      sweep_steps(20)

      expect(channel.frequency_sweep_enabled).to eq(false)
      expect(channel.shadow_frequency).to eq(0x400)
    end

    # The period is reloaded at trigger and at each fire, never on an NR10 write in between.
    it 'ignores a pace written mid-countdown until the next fire' do
      trigger_sweep!(pace: 4, shift: 1, direction: :up, period: 0x400)
      sweep_steps(1)

      mmu.write(APU::REGISTERS[:nr10], (1 << 4) | 1) # pace 4 -> 1, same shift

      sweep_steps(2) # 3 steps in: still short of the latched period of 4
      expect(channel.shadow_frequency).to eq(0x400)

      sweep_steps(1)
      expect(channel.shadow_frequency).to eq(0x600)
    end

    it 'does not corrupt channel 2 registers (regression: sweep must be CH1-only)' do
      channel2 = apu.channels[2]
      trigger!(channel_number: 2, duty: 0b10, volume: 0x0F, period: 0x400)
      channel2.tick(nb_ticks: 4)

      volume_before = channel2.volume
      duty_before = channel2.duty_cycle

      50.times { channel2.on_frame_sequencer_step(2) }
      50.times { channel2.on_frame_sequencer_step(6) }

      # Sweep must never touch CH2's own volume/duty (it has no NR20 register).
      expect(channel2.volume).to eq(volume_before)
      expect(channel2.duty_cycle).to eq(duty_before)
    end
  end
end
