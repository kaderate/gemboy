$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
require_relative '../lib/rom_loader'
require_relative '../lib/mmu'
require_relative '../lib/cpu'
require_relative '../lib/ppu'
require_relative '../lib/apu'

STEPS_PER_RUN = 2_000_000
NB_RUNS = 5

def build_emulator
  rom_bytes = RomLoader.new(ARGV[0] || 'roms/tetris_world_rev1.gb').rom_bytes
  mmu = MMU.new(rom_bytes, debug_config: {})
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

cpu, ppu, apu = build_emulator

# Warmup : laisse YJIT compiler le code chaud avant de mesurer
run_steps(cpu, ppu, apu, 200_000)

opcodes_per_sec = NB_RUNS.times.map do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  run_steps(cpu, ppu, apu, STEPS_PER_RUN)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  rate = STEPS_PER_RUN / elapsed
  puts format('run: %<rate>.0f opcodes/sec (%<elapsed>.3fs)', rate:, elapsed:)
  rate
end.sort

median = opcodes_per_sec[NB_RUNS / 2]
puts format('median: %<median>.0f opcodes/sec', median:)
