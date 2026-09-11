# frozen_string_literal: true

# Runs one benchmark repetition in its own fresh process (JIT state must never carry over
# between reps). Optionally navigates a menu first (deterministic, cycle-scheduled button taps,
# never wall-clock timed), then executes a warmup phase (untimed, lets the JIT compile hot code)
# and a measured phase of a fixed instruction-step budget, both entirely inside genuine ROM
# execution (never in the post-test JR-self trap for test ROMs, never sitting in a menu for
# real games), and prints one CSV line to stdout.
#
# Usage: ruby [--yjit|--zjit] run_one.rb <rom.gb> <warmup_steps> <measured_steps> [nav]
#   nav: comma-separated wait:key taps applied after a 3,000,000-step boot, e.g.
#        "0:start,300000:start,1000000:start" -- validate any new sequence against a
#        framebuffer snapshot (build_emulator + ppu.export_framebuffer_png) before trusting it,
#        a wrong wait silently strands the run on a menu instead of gameplay.

require_relative '../utils'

rom_path, warmup_steps, measured_steps, nav = ARGV
warmup_steps = warmup_steps.to_i
measured_steps = measured_steps.to_i

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
