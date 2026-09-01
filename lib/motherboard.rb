# frozen_string_literal: true

require_relative 'apu'
require_relative 'cpu'
require_relative 'dma'
require_relative 'mmu'
require_relative 'model_selector'
require_relative 'ppu'

# Motherboard is the main object that holds all the components of the Gameboy.
Motherboard = Struct.new(:cpu, :ppu, :apu, :mmu, :dma, :model) do
  def self.build(cartridge, force_cgb: false, debug_config: {}, audio_queue: Thread::Queue.new, logger: nil)
    model = ModelSelector.new(cartridge:, force_cgb:)
    mmu = MMU.from_cartridge(cartridge, debug_config:, model:)
    cpu = CPU.new(mmu, interrupts: mmu.interrupts, timer: mmu.timer, speed_shift: mmu.speed_shift, model:, logger:)

    dma = DMA.new(mmu)
    mmu.attach_dma(dma)
    ppu = PPU.new(mmu, interrupts: mmu.interrupts, dma:, logger:)
    mmu.attach_ppu(ppu)
    apu = APU.new(mmu:, timer: mmu.timer, audio_queue:)
    mmu.attach_apu(apu)

    new(cpu, ppu, apu, mmu, dma, model)
  end
end
