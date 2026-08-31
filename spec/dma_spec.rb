# frozen_string_literal: true

require_relative '../lib/dma'

RSpec.describe DMA do
  ADDR_SOURCE_HIGH = 0xFF51
  ADDR_SOURCE_LOW = 0xFF52
  ADDR_DEST_HIGH = 0xFF53
  ADDR_DEST_LOW = 0xFF54
  ADDR_CONTROL = 0xFF55

  let(:mmu_memory) { Array.new(0x10000, 0) }
  let(:mmu) { double('mmu') }
  subject(:dma) { described_class.new(mmu) }

  before do
    allow(mmu).to receive(:read) { |addr| mmu_memory[addr] }
    allow(mmu).to receive(:write) { |addr, value| mmu_memory[addr] = value }
  end

  def set_source(addr)
    dma.write(ADDR_SOURCE_HIGH, (addr >> 8) & 0xFF)
    dma.write(ADDR_SOURCE_LOW, addr & 0xFF)
  end

  def set_destination(addr)
    dma.write(ADDR_DEST_HIGH, (addr >> 8) & 0xFF)
    dma.write(ADDR_DEST_LOW, addr & 0xFF)
  end

  # bit 7: 0 = GDMA, 1 = HDMA; bits 0-6: length in 16-byte blocks, minus 1
  def start_control_value(mode:, blocks:) = (mode << 7) | (blocks - 1)

  describe 'address registers' do
    it 'ignores the 4 lower bits of the source address' do
      set_source(0xC123)
      set_destination(0x8000)

      dma.write(ADDR_CONTROL, start_control_value(mode: 0, blocks: 1))

      expect(mmu).to have_received(:read).with(0xC120)
    end

    it 'ignores the 4 lower bits of the destination address' do
      set_destination(0x8123)

      dma.write(ADDR_CONTROL, start_control_value(mode: 0, blocks: 1))

      expect(mmu).to have_received(:write).with(0x8120, anything)
    end
  end

  describe 'General-Purpose DMA (bit 7 = 0)' do
    it 'transfers the whole requested length at once' do
      mmu_memory[0xC000, 32] = (1..32).to_a
      set_source(0xC000)
      set_destination(0x8000)

      dma.write(ADDR_CONTROL, start_control_value(mode: 0, blocks: 2)) # 32 bytes

      expect(mmu_memory[0x8000, 32]).to eq((1..32).to_a)
    end

    it 'reports no active transfer once the GDMA completes' do
      set_source(0xC000)
      set_destination(0x8000)

      dma.write(ADDR_CONTROL, start_control_value(mode: 0, blocks: 1))

      expect(dma.read(ADDR_CONTROL)).to eq(0xFF)
    end
  end

  describe 'HBlank DMA (bit 7 = 1)' do
    it 'transfers nothing at the write itself' do
      set_source(0xC000)
      set_destination(0x8000)

      dma.write(ADDR_CONTROL, start_control_value(mode: 1, blocks: 2))

      expect(mmu).not_to have_received(:write)
    end

    it 'transfers exactly one 16-byte block per #advance_hdma_transfer! call' do
      mmu_memory[0xC000, 32] = (1..32).to_a
      set_source(0xC000)
      set_destination(0x8000)
      dma.write(ADDR_CONTROL, start_control_value(mode: 1, blocks: 2)) # 32 bytes, 2 blocks

      dma.advance_hdma_transfer!

      expect(mmu_memory[0x8000, 16]).to eq((1..16).to_a)
      expect(mmu_memory[0x8010, 16]).to eq(Array.new(16, 0)) # second block not transferred yet
    end

    it 'reports the transfer as active with the remaining block count while in progress' do
      set_source(0xC000)
      set_destination(0x8000)
      dma.write(ADDR_CONTROL, start_control_value(mode: 1, blocks: 3))

      dma.advance_hdma_transfer!

      expect(dma.read(ADDR_CONTROL)).to eq((0 << 7) | 1) # active, 1 block-1 remaining (2 blocks left)
    end

    it 'stops on its own once every requested block has been transferred' do
      set_source(0xC000)
      set_destination(0x8000)
      dma.write(ADDR_CONTROL, start_control_value(mode: 1, blocks: 2))

      2.times { dma.advance_hdma_transfer! }
      call_count_before = mmu_memory.dup
      dma.advance_hdma_transfer! # should be a no-op now

      expect(dma.read(ADDR_CONTROL)).to eq(0xFF)
      expect(mmu_memory).to eq(call_count_before)
    end

    it 'cancels an active transfer when bit 7 is written back to 0' do
      set_source(0xC000)
      set_destination(0x8000)
      dma.write(ADDR_CONTROL, start_control_value(mode: 1, blocks: 4))
      dma.advance_hdma_transfer!

      dma.write(ADDR_CONTROL, 0x00) # bit 7 = 0 while a HDMA is active: cancel, not "start a GDMA"

      expect(dma.read(ADDR_CONTROL)).to eq(0xFF)
      expect(mmu).to have_received(:write).exactly(16).times # only the one block from before the cancel
    end
  end

  describe 'transfer termination on invalid ranges' do
    it 'stops the GDMA transfer if the source range becomes invalid mid-transfer' do
      set_source(0xDFF0) # last valid 16-byte-aligned source address in range
      set_destination(0x8000)

      dma.write(ADDR_CONTROL, start_control_value(mode: 0, blocks: 2)) # would read past 0xDFF0 + 16

      expect(mmu).to have_received(:read).with(0xDFFF) # last byte of the valid block
      expect(mmu).not_to have_received(:read).with(0xE000) # first byte past the valid source range
    end
  end
end
