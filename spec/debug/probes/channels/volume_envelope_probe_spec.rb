# frozen_string_literal: true

require_relative '../../../../lib/apu'
require_relative '../../../../lib/debug/probes/channels/volume_envelope_probe'

RSpec.describe Debug::Probes::Channels::VolumeEnvelopeProbe do
  let(:volume_envelope) { APU::VolumeEnvelope.new }

  subject(:probe) { described_class.new(volume_envelope:) }

  it 'expose l enveloppe au repos' do
    expect(probe.snapshot).to eq(volume: 0, envelope_sweep_step: 0)
  end

  it 'suit le volume ecrit' do
    volume_envelope.write_volume(9)

    expect(probe.snapshot).to eq(volume: 9, envelope_sweep_step: 0)
  end

  it 'suit le pas de sweep quand la pace est nulle' do
    volume_envelope.reset(9)
    2.times { volume_envelope.tick(envelope_sweep_pace: 0, increment_volume: false) }

    expect(probe.snapshot).to eq(volume: 9, envelope_sweep_step: 2)
  end

  it 'suit la descente du volume' do
    volume_envelope.reset(9)
    volume_envelope.tick(envelope_sweep_pace: 1, increment_volume: false)

    expect(probe.snapshot).to eq(volume: 8, envelope_sweep_step: 0)
  end
end
