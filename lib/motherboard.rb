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

  def dump(with_rom: true)
    detached = detach_transient(with_rom:)
    Marshal.dump(self)
  ensure
    attach_transient(detached)
  end

  def self.load(bytes, rom_bytes: nil, logger: nil)
    # rubocop:disable-next Security/MarshalLoad -- bytes come from our own #dump, not an external party
    motherboard = Marshal.load(bytes)
    motherboard.cpu.build_opcodes
    motherboard.apu.instance_variable_set(:@audio_queue, Thread::Queue.new)
    motherboard.mmu.mbc.instance_variable_set(:@rom, rom_bytes) if rom_bytes
    [motherboard.cpu, motherboard.ppu].each { |component| component.instance_variable_set(:@logger, logger) }
    motherboard
  end

  private

  # Transients are derived or replaceable state, detached around the dump
  def detach_transient(with_rom:)
    targets = [[apu, :@audio_queue], [cpu, :@opcode_handlers], [cpu, :@logger], [ppu, :@logger]]
    targets << [mmu.mbc, :@rom] unless with_rom

    targets.map { |object, ivar| [object, ivar, object.instance_variable_get(ivar)] }
           .each { |object, ivar, _| object.instance_variable_set(ivar, nil) }
  end

  def attach_transient(transient) = transient&.each { |object, ivar, value| object.instance_variable_set(ivar, value) }
end
