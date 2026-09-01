# frozen_string_literal: true

require_relative '../lib/motherboard'

RSpec.describe Motherboard do
  subject(:motherboard) { described_class.build(build_cartridge(cgb: :only)) }

  it 'builds every core component' do
    expect(motherboard).to have_attributes(cpu: an_instance_of(CPU), ppu: an_instance_of(PPU),
                                           apu: an_instance_of(APU), mmu: an_instance_of(MMU),
                                           dma: an_instance_of(DMA), model: an_instance_of(ModelSelector))
  end

  it 'seeds the I/O registers with the post-boot state' do
    expect(motherboard.mmu.read(0xFF40)).to eq(0x91) # LCDC
  end

  describe 'wiring' do
    it 'routes an HDMA write to the DMA the PPU advances' do
      motherboard.mmu.write(0xFF51, 0x12) # HDMA1, source high byte

      expect(motherboard.ppu.dma.source).to eq(0x1200)
    end

    it 'routes a KEY1 write to the SpeedShift the CPU switches on STOP' do
      motherboard.mmu.write(0xFF4D, 0x01)

      expect(motherboard.cpu.speed_shift.armed).to be(true)
    end

    it 'routes an APU register write to the attached APU' do
      motherboard.mmu.write(0xFF26, 0x00) # NR52, power off

      expect(motherboard.apu.enabled).to be(false)
    end

    it 'routes a PPU register write to the attached PPU' do
      motherboard.mmu.write(0xFF42, 0x42) # SCY

      expect(motherboard.ppu.read_register(0xFF42)).to eq(0x42)
    end

    it 'gives the DMA a reference back to the MMU' do
      expect { motherboard.mmu.write(0xFF55, 0x00) }.not_to raise_error
    end
  end

  describe 'model selection' do
    it 'runs a CGB-only cartridge in CGB mode' do
      expect(described_class.build(build_cartridge(cgb: :only)).model).to be_cgb
    end

    it 'runs a dual-compatible cartridge in DMG mode by default' do
      expect(described_class.build(build_cartridge(cgb: :enhanced)).model).to be_dmg
    end

    it 'runs a dual-compatible cartridge in CGB mode when forced' do
      expect(described_class.build(build_cartridge(cgb: :enhanced), force_cgb: true).model).to be_cgb
    end

    it 'ignores force_cgb on a DMG-only cartridge' do
      expect(described_class.build(build_cartridge(cgb: :none), force_cgb: true).model).to be_dmg
    end

    it 'shares one model between the MMU and the CPU' do
      expect(motherboard.cpu.model).to be(motherboard.mmu.model)
    end
  end

  describe 'injected collaborators' do
    it 'hands the given audio queue to the APU' do
      queue = Thread::Queue.new

      expect(described_class.build(build_cartridge, audio_queue: queue).apu.audio_queue).to be(queue)
    end

    it 'forwards the debug config to the MMU' do
      motherboard = described_class.build(build_cartridge, debug_config: { mmu_serial: true })

      expect(motherboard.mmu.mmu_serial).to be(true)
    end
  end
end
