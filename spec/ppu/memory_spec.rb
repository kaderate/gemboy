# frozen_string_literal: true

require_relative '../../lib/ppu/memory'

RSpec.describe PPU::Memory do
  subject(:memory) { described_class.new(size: 8, base_addr: 0x8000, initial_value: 0) }

  it 'reads back what was written, addressed from base_addr' do
    memory.write(0x8003, 0x42)

    expect(memory.read(0x8003)).to eq(0x42)
  end

  it 'fills with the given initial value' do
    memory = described_class.new(size: 4, base_addr: 0x8000, initial_value: 0xFF)

    expect(memory.read(0x8000)).to eq(0xFF)
  end

  it 'reads several bytes at once as a slice' do
    memory.write(0x8000, 0x11)
    memory.write(0x8001, 0x22)
    memory.write(0x8002, 0x33)

    expect(memory.read(0x8000, 3)).to eq([0x11, 0x22, 0x33])
  end

  it 'supports [] and []= as aliases for read/write' do
    memory[0x8000] = 0x77
    expect(memory[0x8000]).to eq(0x77)
  end

  describe 'dirty tracking' do
    subject(:memory) { described_class.new(size: 8, base_addr: 0x8000, initial_value: 0, dirty_range: 0x8000..0x8003) }

    it 'starts clean' do
      expect(memory.dirty?).to be(false)
    end

    it 'becomes dirty on a write inside dirty_range' do
      memory.write(0x8001, 0x11)

      expect(memory.dirty?).to be(true)
    end

    it 'stays clean on a write outside dirty_range' do
      memory.write(0x8005, 0x11)

      expect(memory.dirty?).to be(false)
    end

    it 'goes back to clean after mark_as_clean!' do
      memory.write(0x8001, 0x11)
      memory.mark_as_clean!

      expect(memory.dirty?).to be(false)
    end
  end

  describe 'empty_range (e.g. OAM 0xFEA0-0xFEFF)' do
    subject(:memory) { described_class.new(size: 0xA0, base_addr: 0xFE00, initial_value: 0xFF, empty_range: 0xA0..0xFF) }

    it 'reads 0xFF in the empty range instead of running past the backing array' do
      expect(memory.read(0xFEA0)).to eq(0xFF)
    end

    it 'reads 0xFF (repeated) for a multi-byte read that falls in the empty range' do
      expect(memory.read(0xFEA0, 3)).to eq([0xFF, 0xFF, 0xFF])
    end

    it 'drops writes to the empty range, leaving it unreadable-as-written' do
      memory.write(0xFEA0, 0x42)

      expect(memory.read(0xFEA0)).to eq(0xFF)
    end

    it 'still writes normally just below the empty range' do
      memory.write(0xFE9F, 0x42)

      expect(memory.read(0xFE9F)).to eq(0x42)
    end
  end
end
