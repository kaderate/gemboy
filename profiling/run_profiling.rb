# frozen_string_literal: true

# Force activation of YJIT (if available)
RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && !RubyVM::YJIT.enabled?

type = ARGV[0] == 'stackprof' ? :stackprof : :vernier
path = ARGV[1]

require_relative 'utils'

if type == :stackprof
  require 'stackprof'
else
  require 'vernier'
end

STEPS = 2_000_000

cpu, ppu, apu = build_emulator(path)

# Warmup : laisse YJIT compiler le code chaud avant de mesurer
run_steps(cpu, ppu, apu, STEPS / 10)

if type == :stackprof
  StackProf.run(mode: :wall, out: 'profiling/stackprof-report.dump', interval: 100) do
    run_steps(cpu, ppu, apu, STEPS)
  end
else
  Vernier.profile(out: 'profiling/vernier-report.json', allocation_interval: 1000) do
    run_steps(cpu, ppu, apu, STEPS)
  end
end
