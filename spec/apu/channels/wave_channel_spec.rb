require_relative '../../../lib/apu'
require_relative '../../../lib/mmu'

RSpec.describe APU::WaveChannel do
  let(:mmu) { MMU.new(Array.new(0x8000, 0x00)) }
  let(:apu) { APU.new(mmu:, audio_queue: Queue.new) }
  let(:channel_args) { { channel_number: 3, mmu:, apu: } }

  def trigger!(dac_on: true, initial_length: 0, output_level: 0b10, period: 0x400, length_enable: false)
    mmu.write(APU::REGISTERS[:nr30], dac_on ? 0x80 : 0x00)
    mmu.write(APU::REGISTERS[:nr31], initial_length)
    mmu.write(APU::REGISTERS[:nr32], output_level << 5)
    mmu.write(APU::REGISTERS[:nr33], period & 0xFF)
    nrx4_value = 0x80 | (length_enable ? 0x40 : 0x00) | ((period >> 8) & 0x07)
    mmu.write(APU::REGISTERS[:nr34], nrx4_value)
  end

  def dirty_registers
    mmu.consume_dirty_apu_registers.transform_keys { APU::REGISTERS_INVERSE[_1] }
  end

  def fill_wave_ram(*nibbles)
    nibbles.each_slice(2).each_with_index do |(hi, lo), i|
      mmu.write(0xFF30 + i, (hi << 4) | lo)
    end
  end

  describe '#tick / trigger' do
    subject(:channel) { described_class.new(**channel_args) }

    it 'is disabled and silent before any trigger' do
      expect(channel.generate_pcm_sample).to eq(0)
    end

    it 'becomes enabled and produces sound after a trigger' do
      fill_wave_ram(*([0xF] * 32)) # every nibble at max amplitude
      trigger!(output_level: 0b01) # 100%
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      expect(channel.generate_pcm_sample).not_to eq(0)
    end

    it 'stays silent if the DAC is off, even when triggered' do
      fill_wave_ram(*([0xF] * 32))
      trigger!(dac_on: false, output_level: 0b01)
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      expect(channel.generate_pcm_sample).to eq(0)
    end

    it 'disables the channel immediately when the DAC is turned off' do
      fill_wave_ram(*([0xF] * 32))
      trigger!(output_level: 0b01)
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      expect(channel.generate_pcm_sample).not_to eq(0)

      mmu.write(APU::REGISTERS[:nr30], 0x00) # DAC off
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      expect(channel.generate_pcm_sample).to eq(0)
    end

    it 'resets the waveform position to 1 on trigger' do
      trigger!
      expect(channel.instance_variable_get(:@waveform).instance_variable_get(:@current_sample)).to eq(1)
    end
  end

  describe '#generate_digital_sample - output level shift' do
    subject(:channel) { described_class.new(**channel_args) }

    before do
      fill_wave_ram(*([0xF] * 32)) # max amplitude sample at every position
    end

    it 'is muted (shift n/a) when output_level is 0' do
      trigger!(output_level: 0b00)
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      expect(channel.generate_digital_sample).to eq(0)
    end

    it 'outputs the full sample (no shift) when output_level is 1 (100%)' do
      trigger!(output_level: 0b01)
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      expect(channel.generate_digital_sample).to eq(0xF)
    end

    it 'outputs a halved sample when output_level is 2 (50%)' do
      trigger!(output_level: 0b10)
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      expect(channel.generate_digital_sample).to eq(0xF >> 1)
    end

    it 'outputs a quartered sample when output_level is 3 (25%)' do
      trigger!(output_level: 0b11)
      channel.tick(nb_ticks: 4, registers: dirty_registers)
      expect(channel.generate_digital_sample).to eq(0xF >> 2)
    end
  end

  describe '#advance_waveform' do
    subject(:channel) { described_class.new(**channel_args) }

    it 'reads consecutive nibbles as the waveform advances, wrapping after 32 samples' do
      fill_wave_ram(0x1, 0x2, 0x3, 0x4, *([0x0] * 28))
      trigger!(output_level: 0b01)
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      # Position starts at 1 (nibble value 0x2) right after trigger.
      expect(channel.generate_digital_sample).to eq(0x2)

      channel.advance_waveform
      expect(channel.generate_digital_sample).to eq(0x3)

      channel.advance_waveform
      expect(channel.generate_digital_sample).to eq(0x4)
    end
  end

  describe '#on_frame_sequencer_step - length timer' do
    subject(:channel) { described_class.new(**channel_args) }

    it 'does nothing when length is not enabled' do
      fill_wave_ram(*([0xF] * 32))
      trigger!(output_level: 0b01, length_enable: false)
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      100.times { channel.on_frame_sequencer_step(0) }

      expect(channel.generate_pcm_sample).not_to eq(0)
    end

    it 'disables the channel once the length timer reaches 0 (target is 256 for the wave channel)' do
      fill_wave_ram(*([0xF] * 32))
      trigger!(output_level: 0b01, length_enable: true)
      channel.tick(nb_ticks: 4, registers: dirty_registers)

      # length_timer starts at 256 - NRx1 = 256 here; step 0 is one of the clocking steps
      260.times { channel.on_frame_sequencer_step(0) }

      expect(channel.generate_pcm_sample).to eq(0)
    end
  end
end
