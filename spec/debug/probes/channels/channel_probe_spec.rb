# frozen_string_literal: true

require_relative '../../../../lib/apu'
require_relative '../../../../lib/debug/probes/channels/channel_probe'

RSpec.describe Debug::Probes::Channels::ChannelProbe do
  let(:mmu) { build_mmu }
  let(:apu) { APU.new(mmu:, audio_queue: Queue.new) }
  let(:channel) { apu.channels[2] }

  subject(:probe) { described_class.new(channel:) }

  before do
    mmu.attach_apu(apu)
    mmu.write(APU::REGISTERS[:nr52], 0x80) # power on, or write_allowed? blocks everything
  end

  def registers = APU::REGISTERS.transform_values { apu.raw(_1) }

  def tick! = channel.tick(nb_ticks: 4)

  it 'ne rend que les registres du canal' do
    mmu.write(APU::REGISTERS[:nr21], 0xC0)
    mmu.write(APU::REGISTERS[:nr11], 0x3F)

    expect(probe.snapshot(registers)[:registers]).to eq(nr21: 0xC0, nr22: 0, nr23: 0, nr24: 0)
  end

  it 'rend les cinq registres du canal 1, sweep compris' do
    probe = described_class.new(channel: apu.channels[1])

    expect(probe.snapshot(registers)[:registers].keys).to eq(%i[nr10 nr11 nr12 nr13 nr14])
  end

  it 'rend les registres du canal wave' do
    probe = described_class.new(channel: apu.channels[3])

    expect(probe.snapshot(registers)[:registers].keys).to eq(%i[nr30 nr31 nr32 nr33 nr34])
  end

  it 'n ajoute aucun etage specifique dans la classe de base' do
    expect(probe.snapshot(registers).keys).to eq(%i[enabled dac_enabled registers length_timer])
  end

  it 'expose le canal eteint avant tout trigger' do
    expect(probe.snapshot(registers)).to include(enabled: false, dac_enabled: false)
  end

  it 'expose le canal allume apres un trigger' do
    mmu.write(APU::REGISTERS[:nr22], 0xF8)
    mmu.write(APU::REGISTERS[:nr24], 0x80)
    tick!

    expect(probe.snapshot(registers)).to include(enabled: true, dac_enabled: true)
  end

  it 'expose l etat du length timer du canal' do
    mmu.write(APU::REGISTERS[:nr21], 0x0A)
    tick!

    expect(probe.snapshot(registers)[:length_timer])
      .to eq(enabled: true, length_timer: 54, length_timer_target: 64, frame_sequencer_step: 0)
  end

  it 'donne acces au canal sonde' do
    expect(probe.channel).to be(channel)
    expect(probe.channel_number).to eq(2)
  end
end
