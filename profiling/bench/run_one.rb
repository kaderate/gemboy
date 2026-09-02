# frozen_string_literal: true

# Runs one benchmark repetition in its own fresh process (JIT state must never carry over
# between reps). Executes a warmup phase (untimed, lets the JIT compile hot code) then a
# measured phase of a fixed instruction-step budget, both entirely inside genuine ROM
# execution (never in the post-test JR-self trap), and prints one CSV line to stdout.
#
# Usage: ruby [--yjit|--zjit] run_one.rb <rom.gb> <warmup_steps> <measured_steps>

require_relative '../utils'

rom_path, warmup_steps, measured_steps = ARGV
warmup_steps = warmup_steps.to_i
measured_steps = measured_steps.to_i

cpu, ppu, apu = build_emulator(rom_path)

run_steps(cpu, ppu, apu, warmup_steps)

start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
total_cycles = run_steps(cpu, ppu, apu, measured_steps)
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

jit =
  if defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
    'yjit'
  elsif defined?(RubyVM::ZJIT) && RubyVM::ZJIT.enabled?
    'zjit'
  else
    'none'
  end

puts [jit, File.basename(rom_path), measured_steps, total_cycles, elapsed].join(',')
