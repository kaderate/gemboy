# frozen_string_literal: true

require_relative '../../../../lib/apu'
require_relative '../../../../lib/debug/probes/channels/pulse_channel_probe'

RSpec.describe Debug::Probes::Channels::PulseChannelProbe do
  let(:mmu) { build_mmu }
  let(:apu) { APU.new(mmu:, audio_queue: Queue.new) }
  let(:channel) { apu.channels[1] }

  subject(:probe) { described_class.new(channel:) }

  def registers = APU::REGISTERS.transform_values { mmu.read(_1) }

  def tick!(channel, nb_ticks: 4)
    dirty = mmu.consume_dirty_apu_registers.transform_keys { APU::REGISTERS_INVERSE[_1] }
    channel.tick(nb_ticks:, registers: dirty)
  end

  def trigger!(channel, duty: 0b10, period: 0x400, sweep: 0x00)
    number = channel.channel_number
    mmu.write(APU::REGISTERS[:"nr#{number}0"], sweep) if number == 1
    mmu.write(APU::REGISTERS[:"nr#{number}1"], duty << 6)
    mmu.write(APU::REGISTERS[:"nr#{number}2"], 0xF8)
    mmu.write(APU::REGISTERS[:"nr#{number}3"], period & 0xFF)
    mmu.write(APU::REGISTERS[:"nr#{number}4"], 0x80 | ((period >> 8) & 0x07))
    tick!(channel)
  end

  it 'ne rend que les registres du canal' do
    trigger!(channel)

    expect(probe.snapshot(registers)[:registers].keys).to eq(%i[nr21 nr22 nr23 nr24])
  end

  it 'expose le rapport cyclique choisi' do
    trigger!(channel, duty: 0b11)

    expect(probe.snapshot(registers)[:duty_cycle]).to eq(3)
  end

  it 'fait avancer le pas de duty au fil des debordements de periode' do
    trigger!(channel, period: 0x7F0)
    100.times { tick!(channel, nb_ticks: 16) }

    expect(probe.snapshot(registers)[:duty_step]).to be_between(1, 7)
  end

  it 'expose l enveloppe de volume du canal' do
    trigger!(channel)

    expect(probe.snapshot(registers)[:volume_envelope]).to eq(volume: 0x0F, envelope_sweep_step: 0)
  end

  it 'expose le diviseur de periode du canal' do
    trigger!(channel, period: 0x400)

    expect(probe.snapshot(registers)[:period_divider]).to include(clock_divider: 4)
  end

  it 'n expose aucun sweep sur le canal 2' do
    trigger!(channel)

    expect(probe.snapshot(registers)[:sweep]).to be_nil
  end

  it 'expose le sweep du canal 1' do
    channel1 = apu.channels[0]
    trigger!(channel1, period: 0x400, sweep: 0x15)

    expect(described_class.new(channel: channel1).snapshot(registers)[:sweep])
      .to eq(enabled: true, step: 0, period: 1, shadow_frequency: 0x400)
  end

  it 'expose l etat commun herite de la classe de base' do
    trigger!(channel)

    expect(probe.snapshot(registers)).to include(enabled: true, dac_enabled: true)
    expect(probe.snapshot(registers)[:length_timer]).to include(length_timer_target: 64)
  end
end
