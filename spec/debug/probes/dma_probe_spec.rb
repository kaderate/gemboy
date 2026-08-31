# frozen_string_literal: true

require_relative '../../../lib/debug/probes/dma_probe'
require_relative '../../../lib/dma'

RSpec.describe Debug::Probes::DMAProbe do
  let(:mmu) { double('mmu', read: 0, write: nil) }
  let(:dma) { DMA.new(mmu) }

  subject(:probe) { described_class.new(dma:) }

  it 'reports no active transfer before anything was written' do
    expect(probe.snapshot).to include(active: false, remaining_blocks: 0)
  end

  it 'reports an active HBlank transfer with its source, destination and remaining blocks' do
    dma.write(0xFF51, 0xC0) # source high
    dma.write(0xFF52, 0x00) # source low
    dma.write(0xFF53, 0x80) # destination high
    dma.write(0xFF54, 0x00) # destination low
    dma.write(0xFF55, (1 << 7) | 1) # HDMA, 2 blocks requested

    expect(probe.snapshot).to include(mode: 'HDMA', active: true, source: 0xC000, destination: 0x8000,
                                      requested_blocks: 2, remaining_blocks: 2)
  end

  it 'reports GDMA as complete right after the (instant) transfer' do
    dma.write(0xFF51, 0xC0)
    dma.write(0xFF52, 0x00)
    dma.write(0xFF53, 0x80)
    dma.write(0xFF54, 0x00)
    dma.write(0xFF55, (0 << 7) | 0) # GDMA, 1 block

    expect(probe.snapshot).to include(mode: 'GDMA', active: false, remaining_blocks: 0)
  end
end
