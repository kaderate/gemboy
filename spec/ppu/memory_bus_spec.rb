# frozen_string_literal: true

require_relative '../../lib/ppu/memory'
require_relative '../../lib/ppu/memory_bus'

RSpec.describe PPU::MemoryBus do
  subject(:bus) { described_class.new(memory) }

  let(:memory) { PPU::Memory.new(size: 4, base_addr: 0x8000, initial_value: 0) }

  it 'is accessible by default' do
    bus.write(0x8000, 0x42)
    expect(bus.read(0x8000)).to eq(0x42)
  end

  it 'reads through to the wrapped memory when accessible' do
    memory.write(0x8001, 0x11)
    expect(bus.read(0x8001)).to eq(0x11)
  end

  it 'writes through to the wrapped memory when accessible' do
    bus.write(0x8002, 0x99)
    expect(memory.read(0x8002)).to eq(0x99)
  end

  it 'reads 0xFF instead of the real byte when inaccessible' do
    memory.write(0x8000, 0x42)
    bus.accessible = false

    expect(bus.read(0x8000)).to eq(0xFF)
  end

  it 'drops writes when inaccessible, leaving the wrapped memory untouched' do
    memory.write(0x8000, 0x42)
    bus.accessible = false

    bus.write(0x8000, 0x99)

    expect(memory.read(0x8000)).to eq(0x42)
  end

  it 'resumes normal access once accessible again' do
    bus.accessible = false
    bus.write(0x8000, 0x99) # dropped
    bus.accessible = true

    bus.write(0x8000, 0x77)

    expect(bus.read(0x8000)).to eq(0x77)
  end

  it "does not gate the wrapped memory's own direct access" do
    bus.accessible = false

    memory.write(0x8000, 0x42)

    expect(memory.read(0x8000)).to eq(0x42)
  end
end
