# frozen_string_literal: true

require_relative '../../lib/ppu'

RSpec.describe PPU::LcdStatus do
  # Minimal doubles: LcdStatus only ever calls ppu.ly, ppu.registers.raw(lyc_addr) and
  # mode_obj.mode_index -- isolating it from the real PPU/Mode lets each of these vary
  # independently, including cases (like a nil mode_index) that Mode itself no longer produces.
  FakeRegisters = Struct.new(:lyc_value) do
    def raw(_addr) = lyc_value
  end
  FakePpu = Struct.new(:ly, :registers)
  FakeMode = Struct.new(:mode_index)

  def build_status(bytes: 0x00, ly: 0, lyc: 0, mode_index: 0)
    ppu = FakePpu.new(ly, FakeRegisters.new(lyc))
    mode_obj = FakeMode.new(mode_index)
    described_class.new(bytes:, ppu:, mode_obj:)
  end

  describe 'stored interrupt-enable bits' do
    it 'reads lyc_interrupt_enable from bit 6' do
      expect(build_status(bytes: 0x40).lyc_interrupt_enable).to be(true)
    end

    it 'reads mode_2_interrupt_enable from bit 5' do
      expect(build_status(bytes: 0x20).mode_2_interrupt_enable).to be(true)
    end

    it 'reads mode_1_interrupt_enable from bit 4' do
      expect(build_status(bytes: 0x10).mode_1_interrupt_enable).to be(true)
    end

    it 'reads mode_0_interrupt_enable from bit 3' do
      expect(build_status(bytes: 0x08).mode_0_interrupt_enable).to be(true)
    end
  end

  describe '#mode' do
    it 'delegates to mode_obj.mode_index' do
      expect(build_status(mode_index: :mode_3).mode).to eq(:mode_3)
    end
  end

  describe '#lyc_equals_ly' do
    it 'is true when LY matches the stored LYC' do
      expect(build_status(ly: 42, lyc: 42).lyc_equals_ly).to be(true)
    end

    it 'is false when LY differs from LYC' do
      expect(build_status(ly: 1, lyc: 2).lyc_equals_ly).to be(false)
    end
  end

  describe '#bytes' do
    it 'combines the stored bits with the live mode and live LYC=LY bit' do
      status = build_status(bytes: 0x40, ly: 5, lyc: 5, mode_index: 0x03)

      expect(status.bytes).to eq(0x40 | 0x03 | 0x04)
    end

    # Regression: mode_obj.mode_index used to be able to return nil (before Mode learned to
    # default to 0), which piped straight into `mode & 0x03` -- TypeError via NilClass#&.
    # LcdStatus guards against it independently of whatever Mode itself does today.
    it 'does not raise when mode_index is nil' do
      status = build_status(mode_index: nil)

      expect { status.bytes }.not_to raise_error
      expect(status.bytes & 0x03).to eq(0)
    end
  end

  describe '#bytes=' do
    it 'keeps only the stored-fields bits (0x78), dropping bit 7 and the mode/LYC bits' do
      status = build_status
      status.bytes = 0xFF

      expect(status.instance_variable_get(:@bytes)).to eq(0x78)
    end

    it 'round-trips through #bytes once combined with a fresh mode/LYC read' do
      status = build_status(ly: 1, lyc: 2, mode_index: 0) # LYC != LY, mode 0
      status.bytes = 0x40 # only the LYC-interrupt-enable bit

      expect(status.bytes).to eq(0x40)
    end
  end
end
