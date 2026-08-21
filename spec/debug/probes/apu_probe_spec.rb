# frozen_string_literal: true

require_relative '../../../lib/debug/probes/apu_probe'

RSpec.describe Debug::Probes::APUProbe do
  let(:mmu) { build_mmu }
  let(:apu) { APU.new(mmu:, audio_queue: Queue.new) }

  subject(:probe) { described_class.new(apu:, mmu:) }

  it 'expose les quatre canaux sous des cles stables' do
    expect(probe.snapshot[:channels].keys).to eq(%i[pulse1 pulse2 wave noise])
  end

  it 'donne a chaque canal ses propres registres' do
    mmu.write(APU::REGISTERS[:nr11], 0xC0)
    mmu.write(APU::REGISTERS[:nr41], 0x3F)

    channels = probe.snapshot[:channels]
    expect(channels[:pulse1][:registers]).to eq(nr10: 0, nr11: 0xC0, nr12: 0, nr13: 0, nr14: 0)
    expect(channels[:noise][:registers]).to eq(nr41: 0x3F, nr42: 0, nr43: 0, nr44: 0)
  end

  it 'expose les registres maitres a part' do
    mmu.write(APU::REGISTERS[:nr50], 0x77)
    mmu.write(APU::REGISTERS[:nr51], 0xF3)

    expect(probe.snapshot[:master]).to eq(nr50: 0x77, nr51: 0xF3, nr52: 0)
  end

  it 'lit les 16 octets de wave RAM' do
    16.times { mmu.write(APU::Waveform::START_ADDRESS + _1, _1) }

    expect(probe.snapshot[:wave_ram]).to eq((0..15).to_a)
  end

  it 'ne deborde pas de la wave RAM sur les registres suivants' do
    mmu.write(APU::REGISTERS[:nr50], 0xAA)

    expect(probe.snapshot[:wave_ram]).not_to include(0xAA)
  end

  it 'active le scope sur l APU a la construction' do
    expect { probe }.to change { apu.scope_buffer }.from(nil).to(be_a(APU::ScopeBuffer))
  end

  it 'ramene les echantillons stereo a une valeur par point' do
    probe
    apu.scope_buffer.write([0.5, -0.5])
    apu.scope_buffer.write([1.0, 0.0])

    expect(probe.snapshot[:scope]).to eq([0.0, 0.5])
  end

  it 'donne a chaque canal son propre scope' do
    probe
    apu.channel_scopes[2].write(0.75)

    expect(probe.snapshot[:channels][:wave][:scope]).to eq([0.75])
    expect(probe.snapshot[:channels][:noise][:scope]).to eq([])
  end

  it 'expose le sweep sur le canal 1 seulement' do
    channels = probe.snapshot[:channels]

    expect(channels[:pulse1][:sweep]).to include(:enabled, :step, :period, :shadow_frequency)
    expect(channels[:pulse2][:sweep]).to be_nil
  end

  it 'expose le LFSR du canal noise' do
    expect(probe.snapshot[:channels][:noise][:lfsr]).to eq(value: 0x7FFF, mode: :long, lsb: 1)
  end

  it 'expose la position de lecture de la waveform' do
    expect(probe.snapshot[:channels][:wave][:position]).to eq(apu.channels[2].waveform.current_sample)
  end
end
