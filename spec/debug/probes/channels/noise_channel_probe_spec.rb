# frozen_string_literal: true

require_relative '../../../../lib/apu'
require_relative '../../../../lib/debug/probes/channels/noise_channel_probe'

RSpec.describe Debug::Probes::Channels::NoiseChannelProbe do
  let(:mmu) { build_mmu }
  let(:apu) { APU.new(mmu:, audio_queue: Queue.new) }
  let(:channel) { apu.channels[4] }

  subject(:probe) { described_class.new(channel:) }

  before do
    mmu.attach_apu(apu)
    mmu.write(APU::REGISTERS[:nr52], 0x80) # power on, or write_allowed? blocks everything
  end

  def registers = APU::REGISTERS.transform_values { mmu.read_io_raw(_1) }

  def tick!(nb_ticks: 4) = channel.tick(nb_ticks:)

  def trigger!
    mmu.write(APU::REGISTERS[:nr42], 0xF8)
    mmu.write(APU::REGISTERS[:nr44], 0x80)
    tick!
  end

  it 'ne rend que les registres du canal' do
    trigger!

    expect(probe.snapshot(registers)[:registers].keys).to eq(%i[nr41 nr42 nr43 nr44])
  end

  it 'expose le LFSR au repos' do
    expect(probe.snapshot(registers)[:lfsr]).to eq(value: 0x7FFF, mode: :long, lsb: 1)
  end

  it 'suit le decalage du LFSR' do
    trigger!
    tick!(nb_ticks: 8)

    expect(probe.snapshot(registers)[:lfsr]).to eq(value: 0x3FFF, mode: :long, lsb: 1)
  end

  it 'expose la periode et la cible du timer de bruit' do
    expect(probe.snapshot(registers)[:noise_timer]).to eq(period: 0, target: 8)
  end

  it 'suit l avancement du timer de bruit' do
    trigger!
    tick!(nb_ticks: 2)

    expect(probe.snapshot(registers)[:noise_timer]).to eq(period: 6, target: 8)
  end

  it 'expose l enveloppe de volume du canal' do
    trigger!

    expect(probe.snapshot(registers)[:volume_envelope]).to eq(volume: 0x0F, envelope_sweep_step: 0)
  end

  it 'n expose pas de diviseur de periode, le canal noise n en a pas' do
    expect(probe.snapshot(registers)).not_to have_key(:period_divider)
  end

  it 'expose l etat commun herite de la classe de base' do
    trigger!

    expect(probe.snapshot(registers)).to include(enabled: true, dac_enabled: true)
    expect(probe.snapshot(registers)[:length_timer]).to include(length_timer_target: 64)
  end
end
