# frozen_string_literal: true

require 'tmpdir'

require_relative '../../lib/save_states/ui'

RSpec.describe SaveStates::UI do
  subject(:ui) { described_class.new(slots) }

  around { |example| Dir.mktmpdir { |dir| @dir = dir and example.run } }

  let(:cartridge) { build_cartridge(rom_path: File.join(@dir, 'game.gb')) }
  let(:slots) { SaveStates::Slots.new(cartridge) }

  def press(scancode) = ui.key_pressed(scancode)

  describe '#key_pressed' do
    it 'ignores a key it does not own' do
      expect(press(SDL::SCANCODE_UP)).to be(false)
    end

    it 'selects the slot of the pressed digit' do
      press(SDL::SCANCODE_3)

      expect(ui.slot).to eq(3)
    end

    it 'queues a save request for the selected slot' do
      press(SDL::SCANCODE_3)
      press(SDL::SCANCODE_F5)

      expect(ui.pop_request).to eq([:save, 3])
    end

    it 'queues a load request for the selected slot' do
      press(SDL::SCANCODE_F8)

      expect(ui.pop_request).to eq([:load, 1])
    end

    it 'starts on slot 1' do
      expect(ui.slot).to eq(1)
    end
  end

  describe '#pop_request' do
    it 'returns nil when nothing was requested' do
      expect(ui.pop_request).to be_nil
    end

    it 'drains the request it returned' do
      press(SDL::SCANCODE_F5)
      ui.pop_request

      expect(ui.pop_request).to be_nil
    end
  end

  describe '#status' do
    it 'is empty until a key is pressed' do
      expect(ui.status).to be_nil
    end

    it 'reports the date of the selected slot' do
      allow(Time).to receive(:now).and_return(Time.at(1_757_250_000))
      slots.save(3, Motherboard.build(cartridge))

      press(SDL::SCANCODE_3)

      expect(ui.status).to eq("Slot 3 · #{Time.at(1_757_250_000).strftime('%d/%m %H:%M')}")
    end

    it 'reports an empty slot' do
      press(SDL::SCANCODE_3)

      expect(ui.status).to eq('Slot 3 · empty')
    end

    it 'reports a completed save' do
      press(SDL::SCANCODE_F5)
      ui.saved(1)

      expect(ui.status).to eq('Slot 1 · saved')
    end

    it 'reports a completed load' do
      ui.loaded(2)

      expect(ui.status).to eq('Slot 2 · loaded')
    end

    it 'reports a failure' do
      ui.failed(2, SaveStates::EmptySlot.new('slot 2 is empty'))

      expect(ui.status).to eq('Slot 2 · slot 2 is empty')
    end
  end
end
