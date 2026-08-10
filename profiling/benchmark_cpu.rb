# frozen_string_literal: true

# Force activation of YJIT (if available)
RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && !RubyVM::YJIT.enabled?

require_relative 'utils'

STEPS_PER_RUN = 2_000_000
NB_RUNS = 5

cpu, ppu, apu = build_emulator(ARGV[0])

# Warmup : laisse YJIT compiler le code chaud avant de mesurer
run_steps(cpu, ppu, apu, STEPS_PER_RUN / 10)

t_cycles_per_sec = NB_RUNS.times.map do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  cycles = run_steps(cpu, ppu, apu, STEPS_PER_RUN)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  rate = cycles / elapsed
  puts format('run: %<rate>.0f T-cycles/sec (%<speed>.2fx, %<per_step>.2f cycles/step, %<elapsed>.3fs)',
              rate:, speed: rate / CPU::T_CYCLES_PER_SECOND.to_f, per_step: cycles.to_f / STEPS_PER_RUN, elapsed:)
  rate
end.sort

median = t_cycles_per_sec[NB_RUNS / 2]
puts format('median: %<median>.0f T-cycles/sec (%<speed>.2fx temps réel)',
            median:, speed: median / CPU::T_CYCLES_PER_SECOND.to_f)
