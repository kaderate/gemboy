# frozen_string_literal: true

# Force activation of YJIT (if available)
RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && !RubyVM::YJIT.enabled?

require_relative 'utils'

STEPS = 2_000_000

cpu, ppu, apu = build_emulator(ARGV[0])
# Warmup : laisse YJIT compiler le code chaud avant de mesurer
run_steps(cpu, ppu, apu, 200_000)

GC.start
before = GC.stat

run_steps(cpu, ppu, apu, STEPS)

after = GC.stat

allocated = after[:total_allocated_objects] - before[:total_allocated_objects]
puts "steps: #{STEPS}"
puts "objects allocated: #{allocated} (#{(allocated.to_f / STEPS).round(2)} per step)"
puts "minor GC runs: #{after[:minor_gc_count] - before[:minor_gc_count]}"
puts "major GC runs: #{after[:major_gc_count] - before[:major_gc_count]}"
puts "GC time: #{((after[:time] - before[:time]) / 1000.0).round(3)}s"
puts "heap_live_slots: #{after[:heap_live_slots]} (before: #{before[:heap_live_slots]})"
