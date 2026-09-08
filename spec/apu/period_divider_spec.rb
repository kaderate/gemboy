require_relative '../../lib/apu/period_divider'

RSpec.describe APU::PeriodDivider do
  # Pulse channels step every 4 APU cycles, the wave channel every 2.
  let(:pulse) { described_class.new(1) }
  let(:wave) { described_class.new(3) }

  # Delivers exactly `total` cycles in packets of `packet`, returns the number of overflows.
  def deliver(divider, total:, packet:, period: 0x400)
    remaining = total
    overflows = 0
    while remaining.positive?
      step = [packet, remaining].min
      overflows += 1 if divider.tick(step, period)
      remaining -= step
    end
    overflows
  end

  describe '#tick' do
    it 'keeps the remainder across calls instead of truncating it' do
      2.times { pulse.tick(2, 0x400) }
      expect(pulse.current_period_div).to eq(1)
    end

    it 'still advances when every packet is smaller than the clock divider' do
      4.times { pulse.tick(1, 0x400) }
      expect(pulse.current_period_div).to eq(1)
    end

    it 'is equivalent to deliver the same cycles in one packet or in several' do
      split = described_class.new(1)
      pulse.tick(4, 0x400)
      2.times { split.tick(2, 0x400) }
      expect(split.current_period_div).to eq(pulse.current_period_div)
    end

    # The bug behind the CGB double-speed pitch drop: T-cycles are always a multiple of 4, but
    # the dots handed to the APU in double speed are only a multiple of 2, and 2 / 4 truncated
    # to 0 froze the pulse channels.
    [1, 3].each do |channel_number|
      it "overflows at the same rate whatever the packet size, for channel #{channel_number}" do
        counts = [1, 2, 4, 8, 16].map { |packet| deliver(described_class.new(channel_number), total: 65_536, packet:) }
        expect(counts.uniq).to eq([counts.first])
      end

      it "overflows at the same rate on packet sizes that straddle a reload, for channel #{channel_number}" do
        counts = [3, 4, 6, 24].map { |packet| deliver(described_class.new(channel_number), total: 65_536, packet:) }
        expect(counts.uniq).to eq([counts.first])
      end
    end

    it 'reloads from the current period on overflow' do
      expect(deliver(pulse, total: 4 * 0x800, packet: 4, period: 0x400)).to eq(1)
      expect(pulse.current_period_div).to eq(0x400)
    end

    it 'reloads from the next period when one has been queued' do
      pulse.update_next_period_div(0x600)
      deliver(pulse, total: 4 * 0x800, packet: 4, period: 0x400)
      expect(pulse.current_period_div).to eq(0x600)
      expect(pulse.next_period_div).to be_nil
    end
  end

  describe '#clock_divider' do
    it 'steps a pulse channel every 4 cycles and the wave channel every 2' do
      expect([pulse.clock_divider, wave.clock_divider]).to eq([4, 2])
    end
  end
end
