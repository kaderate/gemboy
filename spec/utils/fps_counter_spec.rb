require_relative '../../lib/utils/fps_counter'

RSpec.describe FPSCounter do
  it 'starts at 0 with no fps recorded yet' do
    counter = described_class.new
    expect(counter.count).to eq(0)
    expect(counter.last_fps).to eq(0)
  end

  it 'increments the frame count on each update within the same second' do
    counter = described_class.new
    counter.update
    counter.update
    expect(counter.count).to eq(2)
    expect(counter.last_fps).to eq(0) # not rolled over yet
  end

  it 'rolls the count into last_fps once a second has elapsed and resets count' do
    counter = described_class.new
    3.times { counter.update }
    counter.instance_variable_set(:@last_time, Time.now - 2) # simulate elapsed time

    counter.update # 4th frame, triggers the rollover

    expect(counter.last_fps).to eq(4)
    expect(counter.count).to eq(0)
  end

  it 'yields the rolled-over count and previous timestamp when a second has elapsed' do
    counter = described_class.new
    2.times { counter.update }
    counter.instance_variable_set(:@last_time, Time.now - 2)

    yielded_count = nil
    counter.update { |count, _last_time| yielded_count = count }

    expect(yielded_count).to eq(3)
  end
end
