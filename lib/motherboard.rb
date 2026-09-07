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

  # APU#@audio_queue (a Thread::Queue) and CPU#@opcode_handlers (bound Method objects) don't
  # survive Marshal; both are pure derived/replaceable state, nil'd out around the dump and
  # rebuilt on load.
  def dump
    audio_queue = apu.instance_variable_get(:@audio_queue)
    opcode_handlers = cpu.instance_variable_get(:@opcode_handlers)
    apu.instance_variable_set(:@audio_queue, nil)
    cpu.instance_variable_set(:@opcode_handlers, nil)
    Marshal.dump(self)
  ensure
    apu.instance_variable_set(:@audio_queue, audio_queue)
    cpu.instance_variable_set(:@opcode_handlers, opcode_handlers)
  end

  def self.load(bytes)
    # rubocop:disable-next Security/MarshalLoad -- bytes come from our own #dump, not an external party
    motherboard = Marshal.load(bytes)
    motherboard.cpu.build_opcodes
    motherboard.apu.instance_variable_set(:@audio_queue, Thread::Queue.new)
    motherboard
  end
end
