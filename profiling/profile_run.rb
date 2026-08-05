$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
require 'stackprof'
require_relative '../lib/rom_loader'
require_relative '../lib/mmu'
require_relative '../lib/cpu'
require_relative '../lib/ppu'
require_relative '../lib/apu'

cartridge = RomLoader.new('roms/tetris_world_rev1.gb').cartridge
mmu = MMU.from_cartridge(cartridge, debug_config: {})
cpu = CPU.new(mmu, logger: nil)
ppu = PPU.new(mmu, logger: nil)
apu = APU.new(audio_queue: Thread::Queue.new, mmu: mmu)

# Warmup : laisse YJIT compiler le code chaud avant de mesurer
200_000.times do
  nb_cycles = cpu.step
  ppu.tick(nb_cycles)
  apu.tick(nb_cycles)
end

StackProf.run(mode: :wall, out: 'profiling/stackprof-report.dump', interval: 100) do
  2_000_000.times do
    nb_cycles = cpu.step
    ppu.tick(nb_cycles)
    apu.tick(nb_cycles)
  end
end
