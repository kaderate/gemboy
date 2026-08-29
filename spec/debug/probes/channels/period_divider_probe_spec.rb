# frozen_string_literal: true

require_relative '../../../../lib/apu'
require_relative '../../../../lib/debug/probes/channels/period_divider_probe'

RSpec.describe Debug::Probes::Channels::PeriodDividerProbe do
  let(:period_divider) { APU::PeriodDivider.new(1) }

  subject(:probe) { described_class.new(period_divider:) }

  it 'expose le diviseur au repos' do
    expect(probe.snapshot).to eq(clock_divider: 4, current_period_div: 0, next_period_div: nil)
  end

  it 'expose le diviseur d horloge propre au canal wave' do
    expect(described_class.new(period_divider: APU::PeriodDivider.new(3)).snapshot[:clock_divider]).to eq(2)
  end

  it 'suit la periode courante et la periode en attente' do
    period_divider.update_current_period_div(0x300)
    period_divider.update_next_period_div(0x123)

    expect(probe.snapshot).to eq(clock_divider: 4, current_period_div: 0x300, next_period_div: 0x123)
  end

  it 'suit l avancement du diviseur' do
    period_divider.update_current_period_div(0x100)
    period_divider.tick(16, 0)

    expect(probe.snapshot[:current_period_div]).to eq(0x104)
  end
end
