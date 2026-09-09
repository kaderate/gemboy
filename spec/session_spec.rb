# frozen_string_literal: true

require_relative '../lib/session'

RSpec.describe Session do
  # Whole ROM stays zero-filled (NOP) past the entry point, so the CPU can run for many
  # instructions without falling off into unmapped memory; bank_count sized for a couple of frames.
  let(:nop_cartridge) { build_cartridge(rom: build_rom(bank_count: 16)) }

  def build_session(cartridge = nop_cartridge)
    motherboard = Motherboard.build(cartridge)
    motherboard.mmu.joypad.key_state = FakeKeys.new
    described_class.new(motherboard)
  end

  describe '.build' do
    it 'loads a real ROM file and wires a FakeKeys into the joypad' do
      session = described_class.build(File.expand_path('../test_roms/dmg-acid2.gb', __dir__))

      expect(session.motherboard.mmu.joypad.key_state).to be_a(FakeKeys)
    end
  end

  describe '#motherboard' do
    it 'exposes the underlying Motherboard, per D6' do
      motherboard = Motherboard.build(nop_cartridge)

      expect(described_class.new(motherboard).motherboard).to be(motherboard)
    end
  end

  describe '#press / #release / #clear_keys' do
    subject(:session) { build_session }

    def key_state = session.motherboard.mmu.joypad.key_state

    it 'presses several buttons at once (a 4-button hold opens the save menu in Zelda)' do
      session.press(:a, :b, :start, :select)

      expect(key_state).to have_attributes(a: true, b: true, start: true, select: true)
    end

    it 'releases specific buttons without affecting the others' do
      session.press(:a, :b)
      session.release(:a)

      expect(key_state).to have_attributes(a: false, b: true)
    end

    it 'clears every button' do
      session.press(:up, :a)
      session.clear_keys

      expect(key_state).to have_attributes(up: false, down: false, a: false)
    end
  end

  describe '#tap' do
    subject(:session) { build_session }

    it 'presses then releases, advancing emulated time on both sides' do
      pc_before = session.motherboard.cpu.pc

      session.tap(:a, hold_frames: 1, settle_frames: 1)

      expect(session.motherboard.mmu.joypad.key_state.a).to be(false) # released by the time #tap returns
      expect(session.motherboard.cpu.pc).not_to eq(pc_before) # emulated time actually advanced
    end
  end

  describe '#advance_cycles / #advance_frames' do
    subject(:session) { build_session }

    it 'advances at least the requested T-cycles' do
      expect(session.advance_cycles(350)).to be >= 350
    end

    it 'advances at least one frame worth of T-cycles' do
      expect(session.advance_frames(1)).to be >= Session::FRAME_CYCLES
    end
  end

  describe '#read / #debug_read' do
    subject(:session) { build_session }

    it 'reads memory through the bus-gated path' do
      expect { session.read(0xC000) }.not_to raise_error
    end

    it 'reads memory through the debug (bus-bypassing) path' do
      expect { session.debug_read(0x8000) }.not_to raise_error
    end
  end

  describe '#snapshot / .restore' do
    it 'round-trips CPU and MMU state, unaffected by mutations made after the snapshot' do
      session = build_session
      session.motherboard.mmu.write(0xC000, 0x42)
      session.motherboard.cpu.pc = 0x1234

      bytes = session.snapshot
      session.motherboard.mmu.write(0xC000, 0x99)

      restored = described_class.restore(bytes)

      expect(restored.motherboard.mmu.read(0xC000)).to eq(0x42)
      expect(restored.motherboard.cpu.pc).to eq(0x1234)
    end
  end
end
