$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
require_relative '../lib/rom_loader'
require_relative '../lib/mmu'
require_relative '../lib/cpu'
require_relative '../lib/ppu'
require_relative '../lib/apu'

STEPS = 2_000_000

rom_bytes = RomLoader.new(ARGV[0] || 'roms/tetris_world_rev1.gb').rom_bytes
mmu = MMU.new(rom_bytes, debug_config: {})
cpu = CPU.new(mmu, logger: nil)
ppu = PPU.new(mmu, logger: nil)
apu = APU.new(audio_queue: Thread::Queue.new, mmu: mmu)

# Warmup : laisse YJIT compiler le code chaud avant de mesurer
200_000.times do
  nb_cycles = cpu.step
  ppu.tick(nb_cycles)
  apu.tick(nb_cycles)
end

GC.start
before = GC.stat

STEPS.times do
  nb_cycles = cpu.step
  ppu.tick(nb_cycles)
  apu.tick(nb_cycles)
end

after = GC.stat

allocated = after[:total_allocated_objects] - before[:total_allocated_objects]
puts "steps: #{STEPS}"
puts "objects allocated: #{allocated} (#{(allocated.to_f / STEPS).round(2)} per step)"
puts "minor GC runs: #{after[:minor_gc_count] - before[:minor_gc_count]}"
puts "major GC runs: #{after[:major_gc_count] - before[:major_gc_count]}"
puts "GC time: #{((after[:time] - before[:time]) / 1000.0).round(3)}s"
puts "heap_live_slots: #{after[:heap_live_slots]} (before: #{before[:heap_live_slots]})"
