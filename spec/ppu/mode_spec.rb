# frozen_string_literal: true

require_relative '../../lib/ppu'

RSpec.describe PPU::Mode do
  subject(:mode) { described_class.new }

  it 'starts with no name established' do
    expect(mode.name).to be_nil
  end

  # Regression: MODES[nil] is nil, and nil ended up piped into a bitwise `|` (via LcdStatus#bytes)
  # before this method existed -- TypeError instead of a sane default.
  it 'reports mode_index 0 when no name is established yet, instead of nil' do
    expect(mode.mode_index).to eq(0)
  end

  it 'maps each mode name to its STAT mode number' do
    { mode_0: 0, vblank: 1, mode_2: 2, mode_3: 3 }.each do |name, index|
      mode.name = name
      expect(mode.mode_index).to eq(index)
    end
  end

  describe '#update!' do
    it 'selects mode_2 during the OAM scan window' do
      mode.update!(0, 0)
      expect(mode.name).to eq(:mode_2)
    end

    it 'selects mode_3 during pixel transfer' do
      mode.update!(0, 80)
      expect(mode.name).to eq(:mode_3)
    end

    it 'selects mode_0 during HBlank' do
      mode.update!(0, 252)
      expect(mode.name).to eq(:mode_0)
    end

    it 'selects vblank on scanlines 144 and beyond, regardless of cycles' do
      mode.update!(144, 0)
      expect(mode.name).to eq(:vblank)
    end

    it 'returns true when the mode actually changes' do
      expect(mode.update!(0, 0)).to be(true) # nil -> mode_2
    end

    it 'returns false when the mode stays the same' do
      mode.update!(0, 0)
      expect(mode.update!(0, 1)).to be(false) # mode_2 -> mode_2
    end

    # Regression: a scanline value that matches no known range (the old TOTAL_SCANLINES mixup
    # let LY count past 153) silently produced this instead of raising.
    it 'falls back to no name when the scanline value matches no known range' do
      mode.update!(0, 0)
      mode.update!(200, 0) # past VBLANK_SCANLINES (144...154)

      expect(mode.name).to be_nil
    end
  end

  describe '#cycles_until_next_mode_change' do
    it 'counts down to the end of mode_2 (cycle 80)' do
      mode.name = :mode_2
      expect(mode.cycles_until_next_mode_change(10)).to eq(70)
    end

    it 'counts down to the end of mode_3 (cycle 252)' do
      mode.name = :mode_3
      expect(mode.cycles_until_next_mode_change(200)).to eq(52)
    end

    it 'counts down to the end of mode_0 (cycle 456)' do
      mode.name = :mode_0
      expect(mode.cycles_until_next_mode_change(400)).to eq(56)
    end

    it 'counts down to the end of the scanline during vblank' do
      mode.name = :vblank
      expect(mode.cycles_until_next_mode_change(100)).to eq(356)
    end

    it 'returns 0 when no name is established yet' do
      expect(mode.cycles_until_next_mode_change(0)).to eq(0)
    end
  end
end
