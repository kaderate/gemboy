# frozen_string_literal: true

require_relative '../../lib/ppu/register_file'

RSpec.describe PPU::RegisterFile do
  subject(:registers) { described_class.new }

  LCDC = 0xFF40
  BGP  = 0xFF47 # first address after the DMA gap (0xFF46)
  OBP0 = 0xFF48
  WX   = 0xFF4B # last address in RANGE

  describe 'addressing' do
    it 'excludes DMA (0xFF46) from RANGE' do
      expect(described_class::RANGE).not_to include(0xFF46)
    end

    it 'covers exactly the 11 real PPU registers' do
      expect(described_class::RANGE).to eq([0xFF40, 0xFF41, 0xFF42, 0xFF43, 0xFF44, 0xFF45, 0xFF47, 0xFF48, 0xFF49, 0xFF4A,
                                            0xFF4B])
    end

    # Regression: addr - BASE alone misindexes everything from BGP onward because of the DMA
    # gap, silently reading/writing the wrong register (or running off the end for WX).
    it 'gives every address past the DMA gap its own independent slot' do
      registers.write(BGP, 0x11)
      registers.write(OBP0, 0x22)
      registers.write(WX, 0x33)

      expect(registers.raw(BGP)).to eq(0x11)
      expect(registers.raw(OBP0)).to eq(0x22)
      expect(registers.raw(WX)).to eq(0x33)
    end

    it 'does not let a write to one address bleed into its neighbor' do
      registers.write(BGP, 0xAB)

      expect(registers.raw(OBP0)).not_to eq(0xAB)
    end
  end

  describe '#read' do
    it 'reads back what was written when nothing is masked (LCDC)' do
      registers.write(LCDC, 0x91)

      expect(registers.read(LCDC)).to eq(0x91)
    end

    it 'reads 0 on a fresh file' do
      expect(registers.read(LCDC)).to eq(0x00)
    end
  end

  describe '#raw vs #load' do
    it 'load reaches the byte the same way write does, for a plain register' do
      registers.load(BGP, 0xE4)

      expect(registers.raw(BGP)).to eq(0xE4)
    end

    it 'raw reflects whatever was last stored, by #write or #load' do
      registers.write(BGP, 0x11)
      expect(registers.raw(BGP)).to eq(0x11)

      registers.load(BGP, 0x22)
      expect(registers.raw(BGP)).to eq(0x22)
    end
  end

  describe '#clear_registers!' do
    it 'resets every register back to 0' do
      registers.write(BGP, 0xFF)
      registers.clear_registers!

      expect(registers.raw(BGP)).to eq(0x00)
    end
  end
end
