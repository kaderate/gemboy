require_relative '../lib/screen'

RSpec.describe Screen do
  def make_screen(render_queue:)
    described_class.new(render_queue:, fps_queue: Thread::Queue.new, key_state: nil)
  end

  def fake_frame(color = 0)
    Array.new(Screen::WINDOW_WIDTH * Screen::WINDOW_HEIGHT, color)
  end

  describe '#handle_quit' do
    it 'exits with status 0 so the at_exit hook still saves battery RAM' do
      screen = make_screen(render_queue: Thread::Queue.new)

      expect { screen.handle_quit }.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
    end
  end

  describe '#draw_frame' do
    it 'drains the entire backlog in one call, keeping only the newest frame (fix: unbounded render_queue backlog)' do
      render_queue = Thread::Queue.new
      screen = make_screen(render_queue:)
      allow(SDL).to receive(:UpdateTexture)

      5.times { render_queue << fake_frame }

      screen.draw_frame

      # If production ever outpaces the display's vsync-locked consumption rate,
      # a backlog must never accumulate: every call fully catches up to the
      # latest frame instead of draining one at a time.
      expect(render_queue).to be_empty
    end

    it 'displays the most recently queued frame, discarding older ones' do
      render_queue = Thread::Queue.new
      screen = make_screen(render_queue:)
      allow(SDL).to receive(:UpdateTexture)

      older_frame = fake_frame(0)
      newest_frame = fake_frame(1)
      render_queue << older_frame
      render_queue << newest_frame

      screen.draw_frame

      expect(screen.instance_variable_get(:@blob)).to eq(newest_frame.map { |c| Screen::COLOR_RGBA_SDL.fetch(c) }.pack('N*'))
      expect(render_queue).to be_empty
    end

    it 'keeps the last displayed frame when the queue is empty' do
      render_queue = Thread::Queue.new
      screen = make_screen(render_queue:)
      allow(SDL).to receive(:UpdateTexture)

      render_queue << fake_frame(2)
      screen.draw_frame
      blob_after_frame = screen.instance_variable_get(:@blob)

      screen.draw_frame # queue now empty

      expect(screen.instance_variable_get(:@blob)).to eq(blob_after_frame)
    end
  end
end
