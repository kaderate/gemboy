# frozen_string_literal: true

require 'logger'

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

  describe '#dump / .load' do
    it 'round-trips CPU and MMU state, unaffected by mutations made after the dump' do
      original = motherboard
      original.mmu.write(0xC000, 0x42)
      original.cpu.pc = 0x1234

      bytes = original.dump
      original.mmu.write(0xC000, 0x99)

      loaded = described_class.load(bytes)

      expect(loaded.mmu.read(0xC000)).to eq(0x42)
      expect(loaded.cpu.pc).to eq(0x1234)
    end

    it 'keeps the loaded components wired to each other, not to the original ones' do
      loaded = described_class.load(motherboard.dump)

      expect(loaded.cpu.mmu).to be(loaded.mmu)
      expect(loaded.cpu.mmu).not_to be(motherboard.mmu)
    end

    it 'lets the CPU keep executing after loading (opcode dispatch survives Marshal)' do
      original = described_class.build(build_cartridge(rom: build_rom(bytes: [0x00], at: 0x100))) # NOP
      original.cpu.pc = 0x100

      loaded = described_class.load(original.dump)

      expect { loaded.cpu.step }.not_to raise_error
    end

    it 'lets the APU keep sampling after loading (audio queue survives Marshal)' do
      loaded = described_class.load(motherboard.dump)

      expect { loaded.apu.tick(4) }.not_to raise_error
    end

    it 'restores the original motherboard to a working state once the dump completes' do
      expect { motherboard.dump }.not_to raise_error
      expect { motherboard.cpu.step }.not_to raise_error
    end

    context 'with a logger' do
      # Engine always passes one, with a custom formatter: a Proc, which Marshal refuses.
      let(:logger) { Logger.new(File::NULL).tap { _1.formatter = proc { |_s, _dt, _p, msg| msg } } }

      it 'dumps a motherboard wired to a logger' do
        motherboard = described_class.build(build_cartridge, logger:)

        expect { motherboard.dump }.not_to raise_error
      end

      it 'reattaches the given logger on load' do
        bytes = described_class.build(build_cartridge, logger:).dump

        loaded = described_class.load(bytes, logger:)

        expect(loaded.cpu.instance_variable_get(:@logger)).to be(logger)
        expect(loaded.ppu.instance_variable_get(:@logger)).to be(logger)
      end

      it 'leaves the dumped motherboard with its own logger' do
        motherboard = described_class.build(build_cartridge, logger:)

        motherboard.dump

        expect(motherboard.cpu.instance_variable_get(:@logger)).to be(logger)
      end
    end

    context 'without the ROM' do
      let(:cartridge) { build_cartridge(cgb: :only) }
      let(:motherboard) { described_class.build(cartridge) }

      it 'leaves the ROM out of the payload' do
        expect(motherboard.dump(with_rom: false).bytesize).to be < motherboard.dump.bytesize
      end

      it 'reattaches the given ROM on load' do
        loaded = described_class.load(motherboard.dump(with_rom: false), rom_bytes: cartridge.rom_bytes)

        expect(loaded.mmu.mbc.rom).to be(cartridge.rom_bytes)
      end

      it 'leaves the dumped motherboard with its own ROM' do
        motherboard.dump(with_rom: false)

        expect(motherboard.mmu.mbc.rom).to be(cartridge.rom_bytes)
      end
    end
  end

  describe '#run_steps' do
    subject(:motherboard) { described_class.build(build_cartridge(rom: build_rom(bytes: Array.new(40, 0x00), at: 0x100))) }

    it 'steps the CPU an exact instruction count and returns the total T-cycles consumed' do
      expect(motherboard.run_steps(10)).to eq(40) # NOP: 4 T-cycles each
    end

    it 'leaves the CPU past the last stepped instruction' do
      motherboard.run_steps(10)

      expect(motherboard.cpu.pc).to eq(0x10A)
    end
  end

  describe '#run_cycles' do
    subject(:motherboard) { described_class.build(build_cartridge(rom: build_rom(bytes: Array.new(200, 0x00), at: 0x100))) }

    it 'consumes at least the requested T-cycles' do
      expect(motherboard.run_cycles(350)).to be >= 350
    end

    it 'overshoots by no more than one chunk (20 instructions)' do
      total = motherboard.run_cycles(350)

      expect(total - 350).to be < (20 * 4) # NOP: 4 T-cycles each, so a chunk is at most 80 cycles here
    end
  end
end
