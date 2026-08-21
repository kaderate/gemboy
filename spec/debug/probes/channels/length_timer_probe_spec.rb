# frozen_string_literal: true

require_relative '../../../../lib/apu'
require_relative '../../../../lib/debug/probes/channels/length_timer_probe'

RSpec.describe Debug::Probes::Channels::LengthTimerProbe do
  let(:length_timer) { APU::LengthTimer.new(1) }

  subject(:probe) { described_class.new(length_timer:) }

  it 'expose le timer au repos' do
    expect(probe.snapshot).to eq(enabled: false, length_timer: 0, length_timer_target: 64, frame_sequencer_step: 0)
  end

  it 'suit le rechargement du compteur' do
    length_timer.reload(initial_length: 10)

    expect(probe.snapshot).to include(enabled: true, length_timer: 54)
  end

  it 'suit le pas du frame sequencer et la decrementation' do
    length_timer.reload(initial_length: 10)
    length_timer.clock(2, length_enable: true)

    expect(probe.snapshot).to include(length_timer: 53, frame_sequencer_step: 2)
  end

  it 'expose la cible propre au canal wave' do
    expect(described_class.new(length_timer: APU::LengthTimer.new(3)).snapshot[:length_timer_target]).to eq(256)
  end
end
