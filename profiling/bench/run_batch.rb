# frozen_string_literal: true

# Boots (and, for real games, navigates the menu into gameplay) exactly ONCE, then fork()s one
# child per repetition. Each child inherits the already-booted, already-JIT-warmed process
# state via copy-on-write memory instead of repeating the expensive boot+nav from scratch --
# the dominant cost for the real-game profiles (a Blargg test ROM has no nav at all). Prints
# one CSV line per rep to stdout, in the same 5-field shape run_one.rb used.
#
# Fork isolation is still real isolation: each child gets its own address space and its own
# GC, so one rep's garbage or heap growth cannot bleed into another's measurement. What it
# removes is process*-startup* variance (Ruby boot, bundler, requires, boot+nav) as a noise
# source, since every child starts from a bit-for-bit identical memory snapshot -- arguably
# tighter isolation than a fresh `ruby` invocation per rep, not looser.
#
# Usage: ruby [--yjit|--zjit] run_batch.rb <rom.gb> <warmup_steps> <measured_steps> <reps> [nav]

require_relative '../utils'

rom_path, warmup_steps, measured_steps, reps, nav = ARGV
warmup_steps = warmup_steps.to_i
measured_steps = measured_steps.to_i
reps = reps.to_i

cpu, ppu, apu = build_emulator(rom_path, with_input: !nav.nil?)

if nav
  keys = cpu.mmu.joypad.key_state
  run_steps(cpu, ppu, apu, 3_000_000)
  nav.split(',').each do |tap|
    wait, key = tap.split(':')
    run_steps(cpu, ppu, apu, wait.to_i) if wait.to_i.positive?
    keys.press(key.to_sym)
    run_steps(cpu, ppu, apu, 40_000)
    keys.clear
    run_steps(cpu, ppu, apu, 60_000)
  end
end

jit =
  if defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
    'yjit'
  elsif defined?(RubyVM::ZJIT) && RubyVM::ZJIT.enabled?
    'zjit'
  else
    'none'
  end

reps.times do
  reader, writer = IO.pipe
  pid = fork do
    reader.close
    run_steps(cpu, ppu, apu, warmup_steps)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    total_cycles = run_steps(cpu, ppu, apu, measured_steps)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    writer.puts [jit, File.basename(rom_path), measured_steps, total_cycles, elapsed].join(',')
    writer.close
    exit!(0)
  end
  writer.close
  line = reader.read
  reader.close
  Process.wait(pid)
  puts line
end
