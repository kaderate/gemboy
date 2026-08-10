# frozen_string_literal: true

require_relative '../lib/rom_loader'
require_relative '../lib/mmu'
require_relative '../lib/cpu'
require_relative '../lib/ppu'
require_relative '../lib/apu'

def build_emulator(path)
  cartridge = RomLoader.new(path || 'roms/tetris_world_rev1.gb').cartridge
  mmu = MMU.from_cartridge(cartridge, debug_config: {})
  cpu = CPU.new(mmu, logger: nil)
  ppu = PPU.new(mmu, logger: nil)
  apu = APU.new(audio_queue: Thread::Queue.new, mmu: mmu)
  [cpu, ppu, apu]
end

def run_steps(cpu, ppu, apu, count)
  count.times do
    nb_cycles = cpu.step
    ppu.tick(nb_cycles)
    apu.tick(nb_cycles)
  end
end
