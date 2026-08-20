# frozen_string_literal: true

require_relative '../../lib/debug/collector'

RSpec.describe Debug::Collector do
  class CountingProbe
    attr_reader :calls

    def initialize
      @calls = 0
    end

    def snapshot
      @calls += 1
      { calls: @calls }
    end
  end

  let(:probe) { CountingProbe.new }

  subject(:collector) { described_class.new(probes: { counting: probe }, frame_interval: 3) }

  it 'ne prend un snapshot qu une frame sur frame_interval' do
    2.times { expect(collector.frame_completed!).to be_nil }
    expect(collector.frame_completed!).to eq(counting: { calls: 1 })
    expect(probe.calls).to eq(1)
  end

  it 'repart a zero apres un snapshot' do
    6.times { collector.frame_completed! }
    expect(probe.calls).to eq(2)
  end

  it 'expose le dernier snapshot en ruby nu' do
    collector.sample!
    collector.sample!
    expect(collector.latest).to eq(counting: { calls: 2 })
  end

  it 'incremente sequence a chaque snapshot' do
    expect { collector.sample! }.to change(collector, :sequence).from(0).to(1)
  end

  it 'ne publie rien tant qu aucun snapshot n a ete pris' do
    expect(collector.latest).to be_nil
    expect(collector.sequence).to eq(0)
  end

  it 'accepte de tourner sans aucune sonde' do
    empty = described_class.new(probes: {}, frame_interval: 1)
    expect(empty.frame_completed!).to eq({})
  end
end
