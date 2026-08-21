# frozen_string_literal: true

require_relative '../../../../lib/apu'
require_relative '../../../../lib/debug/probes/channels/wave_channel_probe'

RSpec.describe Debug::Probes::Channels::WaveChannelProbe do
  let(:mmu) { build_mmu }
  let(:apu) { APU.new(mmu:, audio_queue: Queue.new) }
  let(:channel) { apu.channels[2] }

  subject(:probe) { described_class.new(channel:) }

  def registers = APU::REGISTERS.transform_values { mmu.read(_1) }

  def tick!(nb_ticks: 4)
    dirty = mmu.consume_dirty_apu_registers.transform_keys { APU::REGISTERS_INVERSE[_1] }
    channel.tick(nb_ticks:, registers: dirty)
  end

  def trigger!(output_level: 0b01, period: 0x400)
    mmu.write(APU::REGISTERS[:nr30], 0x80)
    mmu.write(APU::REGISTERS[:nr32], output_level << 5)
    mmu.write(APU::REGISTERS[:nr33], period & 0xFF)
    mmu.write(APU::REGISTERS[:nr34], 0x80 | ((period >> 8) & 0x07))
    tick!
  end

  it 'ne rend que les registres du canal' do
    trigger!

    expect(probe.snapshot(registers)[:registers].keys).to eq(%i[nr30 nr31 nr32 nr33 nr34])
  end

  it 'expose le niveau de sortie' do
    trigger!(output_level: 0b10)

    expect(probe.snapshot(registers)[:output_level]).to eq(2)
  end

  it 'expose la position de lecture de la waveform' do
    expect(probe.snapshot(registers)[:position]).to eq(1)
  end

  it 'suit l avancement de la position de lecture' do
    trigger!(period: 0x7F0)
    50.times { tick!(nb_ticks: 16) }

    expect(probe.snapshot(registers)[:position]).to be_between(0, APU::Waveform::WAVEFORM_LENGTH - 1)
    expect(probe.snapshot(registers)[:position]).not_to eq(1)
  end

  it 'expose le diviseur de periode du canal' do
    trigger!

    expect(probe.snapshot(registers)[:period_divider]).to include(clock_divider: 2)
  end

  it 'n expose pas d enveloppe de volume, le canal wave n en a pas' do
    expect(probe.snapshot(registers)).not_to have_key(:volume_envelope)
  end

  it 'expose l etat commun herite de la classe de base' do
    trigger!

    expect(probe.snapshot(registers)).to include(enabled: true, dac_enabled: true)
    expect(probe.snapshot(registers)[:length_timer]).to include(length_timer_target: 256)
  end
end
