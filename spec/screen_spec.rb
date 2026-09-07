require_relative '../lib/screen'
require_relative '../lib/save_states/ui'

RSpec.describe Screen do
  def make_screen(render_queue:, **options)
    described_class.new(render_queue:, fps_queue: Thread::Queue.new, key_state: nil, **options)
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

      expect(screen.instance_variable_get(:@blob)).to eq(newest_frame.pack('N*'))
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

  describe '#draw_stats' do
    let(:overlay) { instance_double(Screen::Overlay, update: nil, flash: nil, visible?: true) }

    before { allow(SDL).to receive(:UpdateTexture) }

    def screen_with_overlays(**options)
      make_screen(render_queue: Thread::Queue.new, **options).tap do |screen|
        screen.instance_variable_set(:@overlays, Hash.new(overlay))
      end
    end

    it 'flashes the save state status when it changes' do
      ui = instance_double(SaveStates::UI, status: 'Slot 3 · saved')

      screen_with_overlays(save_state_ui: ui).draw_stats

      expect(overlay).to have_received(:flash).with(anything, 'Slot 3 · saved')
    end

    it 'shows the key reminder while no status is flashed' do
      allow(overlay).to receive(:visible?).and_return(false)

      screen_with_overlays(save_state_ui: instance_double(SaveStates::UI, status: nil)).draw_stats

      expect(overlay).to have_received(:update).with(anything, Screen::SAVE_STATE_HELP)
    end

    it 'brings the key reminder back once the status flash expired' do
      ui = instance_double(SaveStates::UI, status: 'Slot 3 · saved')
      screen = screen_with_overlays(save_state_ui: ui)
      screen.draw_stats
      allow(overlay).to receive(:visible?).and_return(false)

      screen.draw_stats

      expect(overlay).to have_received(:update).with(anything, Screen::SAVE_STATE_HELP)
    end

    it 'flashes a given status only once' do
      ui = instance_double(SaveStates::UI, status: 'Slot 3 · saved')
      screen = screen_with_overlays(save_state_ui: ui)

      2.times { screen.draw_stats }

      expect(overlay).to have_received(:flash).with(anything, 'Slot 3 · saved').once
    end

    it 'draws no overlay at all when they are turned off' do
      ui = instance_double(SaveStates::UI, status: 'Slot 3 · saved')

      screen_with_overlays(save_state_ui: ui, show_overlays: false).draw_stats

      expect(overlay).not_to have_received(:update)
      expect(overlay).not_to have_received(:flash)
    end
  end

  describe Screen::Overlay do
    subject(:overlay) { described_class.new(**overlay_args) }

    let(:overlay_args) { { renderer: :renderer, x: 100, y_origin: 0, text_color: :black, font: :font } }

    before do
      allow(SDL).to receive_messages(TTF_RenderUTF8_Solid: instance_double(FFI::Pointer, null?: false),
                                     CreateTextureFromSurface: :texture)
      allow(SDL).to receive(:FreeSurface)
      allow(SDL).to receive(:DestroyTexture)
      allow(SDL::Surface).to receive(:new).and_return({ w: 40, h: 10 })
      allow(SDL::Rect).to receive(:new).and_return({})
    end

    it 'stays hidden until something is drawn into it' do
      expect(overlay).not_to be_visible(1)
    end

    it 'stays visible forever without a TTL' do
      overlay.update(100, 'FPS: 60')

      expect(overlay).to be_visible(100_000)
    end

    describe '#flash' do
      subject(:overlay) { described_class.new(**overlay_args, ttl: 240) }

      it 'shows the content right away' do
        overlay.flash(100, 'Slot 3 · saved')

        expect(overlay).to be_visible(101)
      end

      it 'hides it once the TTL has elapsed' do
        overlay.flash(100, 'Slot 3 · saved')

        expect(overlay).not_to be_visible(340)
      end

      it 'restarts the TTL when flashed again with the same content' do
        overlay.flash(100, 'Slot 3 · saved')
        overlay.flash(300, 'Slot 3 · saved')

        expect(overlay).to be_visible(400)
      end

      it 'drops the TTL when updated with permanent content' do
        overlay.flash(100, 'Slot 3 · saved')
        overlay.update(140, '1-9 slot · F5/F8')

        expect(overlay).to be_visible(100_000)
      end
    end

    it 'right-aligns its rectangle on the anchor when asked to' do
      described_class.new(**overlay_args, align: :right).update(100, 'Slot 3 · saved')

      expect(SDL::Rect.new).to include(x: 60) # 100 - 40 wide
    end

    it 'left-aligns its rectangle by default' do
      overlay.update(100, 'Slot 3 · saved')

      expect(SDL::Rect.new).to include(x: 100)
    end
  end
end
