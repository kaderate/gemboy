# frozen_string_literal: true

require_relative '../../lib/apu'

RSpec.describe APU::RegisterFile do
  subject(:registers) { described_class.new }

  NR10 = 0xFF10 # read mask 0x80: bit 7 is never driven
  NR12 = 0xFF12 # read mask 0x00: fully readable
  NR13 = 0xFF13 # read mask 0xFF: stored but never readable
  NR52 = 0xFF26 # read mask 0x70, write mask 0x80
  WAVE = 0xFF30 # plain storage

  describe APU::Register do
    it 'ors the read mask into the stored byte on read' do
      expect(described_class.new(0x0A, 0xF0, 0xFF).read).to eq(0xFA)
    end

    it 'stores the byte untouched when every bit is writable' do
      register = described_class.new(0x00, 0x00, 0xFF)
      register.write(0x5A)

      expect(register.stored).to eq(0x5A)
    end

    it 'leaves the bits outside the write mask alone' do
      register = described_class.new(0b1010_0000, 0x00, 0b0000_1111)
      register.write(0b0101_0101)

      expect(register.stored).to eq(0b1010_0101)
    end

    it 'does not mask the stored byte, only the value read back' do
      register = described_class.new(0x00, 0xFF, 0xFF)
      register.write(0x34)

      expect(register.stored).to eq(0x34)
      expect(register.read).to eq(0xFF)
    end
  end

  describe 'addressing' do
    it 'covers 0xFF10 to 0xFF3F' do
      expect(described_class::RANGE).to eq(0xFF10..0xFF3F)
      expect(described_class::READ_MASKS.size).to eq(48)
      expect(described_class::WRITE_MASKS.size).to eq(48)
    end

    it 'gives each address its own byte' do
      registers.write(NR12, 0x11)
      registers.write(WAVE, 0x22)

      expect(registers.read(NR12)).to eq(0x11)
      expect(registers.read(WAVE)).to eq(0x22)
    end
  end

  describe '#read' do
    it 'returns the written value when nothing is masked' do
      registers.write(NR12, 0x5A)

      expect(registers.read(NR12)).to eq(0x5A)
    end

    it 'forces the undriven bits to 1' do
      registers.write(NR10, 0x00)

      expect(registers.read(NR10)).to eq(0x80)
    end

    it 'returns 0xFF for a write-only register whatever was written' do
      registers.write(NR13, 0x34)

      expect(registers.read(NR13)).to eq(0xFF)
    end

    it 'reads 0 on a fresh file, masks aside' do
      expect(registers.read(NR12)).to eq(0x00)
      expect(registers.read(NR10)).to eq(0x80)
    end
  end

  describe '#write' do
    it 'keeps NR52 channel status bits out of reach' do
      registers.write(NR52, 0xFF)

      expect(registers.read(NR52)).to eq(0xF0)
    end

    it 'still lets NR52 carry the power bit' do
      registers.write(NR52, 0x00)
      expect(registers.read(NR52)).to eq(0x70)

      registers.write(NR52, 0x80)
      expect(registers.read(NR52)).to eq(0xF0)
    end
  end

  describe '#raw' do
    it 'returns the stored byte, mask aside' do
      registers.write(NR13, 0x34)

      expect(registers.raw(NR13)).to eq(0x34)
      expect(registers.read(NR13)).to eq(0xFF)
    end
  end

  describe '#load' do
    it 'reaches bits a bus write cannot' do
      registers.load(NR52, 0xF1)

      expect(registers.raw(NR52)).to eq(0xF1)
    end

    it 'bypasses the write mask where #write would not' do
      registers.write(NR52, 0xF1)

      expect(registers.raw(NR52)).to eq(0x80)
    end
  end

  # The contract dmg_sound/01-registers checks: read back == written | mask, for every value of
  # every register. Masks transcribed from Blargg's source, not read from the class under test.
  describe 'read-back contract (dmg_sound 01, test 2)' do
    BLARGG_MASKS = [
      0x80, 0x3F, 0x00, 0xFF, 0xBF,
      0xFF, 0x3F, 0x00, 0xFF, 0xBF,
      0x7F, 0xFF, 0x9F, 0xFF, 0xBF,
      0xFF, 0xFF, 0x00, 0x00, 0xBF,
      0x00, 0x00, 0x70,
      *([0xFF] * 9),
      *([0x00] * 16)
    ].freeze

    it 'holds for the 47 registers the ROM sweeps, over all 256 values' do
      mismatches = []

      256.times do |value|
        BLARGG_MASKS.each_with_index do |mask, index|
          addr = 0xFF10 + index
          next if addr == NR52 # skipped by test_rw, covered by its own sub-test

          registers.write(addr, value)
          got = registers.read(addr)
          mismatches << [addr, value, mask | value, got] if got != (mask | value)
        end
      end

      expect(mismatches).to be_empty
    end
  end
end
