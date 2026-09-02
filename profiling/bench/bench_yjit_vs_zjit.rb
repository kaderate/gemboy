# frozen_string_literal: true

# Orchestrates the YJIT vs ZJIT vs no-JIT comparison: for each (profile, mode) pair, spawns a
# single `run_batch.rb` process that boots (and, for real games, navigates) ONCE, then fork()s
# `reps` children off that already-booted state to collect `reps` independent measurements
# (see run_batch.rb for why forking is still real isolation, not a shortcut).
#
# This intentionally trades the earlier "interleave every mode within every rep" ordering
# (which spread thermal/scheduler drift evenly across configurations) for wall-clock budget:
# repeating a real game's menu navigation once per rep was the dominant cost by far. All reps
# of a given (profile, mode) now run back-to-back instead. Rerun with run_one.rb's per-process
# loop (still in this directory) if drift-order rigor matters more than a ~10min total budget.
#
# Usage: ruby bench_yjit_vs_zjit.rb [reps] [out.csv]
#
# RUBY env var overrides the interpreter binary used for the child processes (defaults to
# RbConfig.ruby, i.e. whichever `ruby` invoked this script).

require 'rbconfig'

REPS = (ARGV[0] || 6).to_i
OUT_CSV = ARGV[1] || 'bench_results.csv'
RUBY = ENV['RUBY'] || RbConfig.ruby
RUN_BATCH = File.join(__dir__, 'run_batch.rb')

# warmup_steps / measured_steps are chosen per ROM so warmup+measured stays well under that
# ROM's completion cycle count (calibrated by hand against run_test.rb before this table was
# written -- cpu_instrs completes at 224M cycles, dmg_sound at 86M, mem_timing at only 7M so
# it gets a much smaller budget; sprite_ppu never completes, it renders forever, so it has no
# ceiling to respect). Never widen a budget without re-checking it against the real ceiling --
# drifting into the post-test JR-self trap (see rom_test_runner.rb) would measure a trivial
# 2-byte loop instead of the profile's actual workload.
# tetris/sml2 are real commercial ROMs, not versioned in the repo (roms/* is gitignored) --
# they only run when a checkout happens to have them locally. `nav` is a deterministic,
# cycle-scheduled button-tap sequence (never wall-clock timed) validated by hand against
# screenshots: it boots the ROM for 3,000,000 steps then taps each `wait:key` pair (40,000
# steps held, 60,000 released) to walk the menus into actual gameplay -- see navigate.rb.
# Re-validate with a snapshot before touching either sequence: a game update, a different
# ROM revision, or a wrong wait can silently strand the run on a menu instead of gameplay.
PROFILES = {
  'cpu_instrs'  => { rom: 'test_roms/cpu_instrs/cpu_instrs.gb',          warmup: 150_000, measured: 200_000 },
  'dmg_sound'   => { rom: 'test_roms/dmg_sound/dmg_sound.gb',            warmup: 150_000, measured: 200_000 },
  'mem_timing'  => { rom: 'test_roms/mem_timing/mem_timing.gb',          warmup: 50_000,  measured: 80_000 },
  'sprite_ppu'  => { rom: 'test_roms/homemade/build/display_sprite_1.gb', warmup: 150_000, measured: 200_000 },
  'tetris'      => { rom: 'roms/tetris_world.gb', warmup: 150_000, measured: 200_000,
                      nav: '0:start,200000:start,200000:start' },
  'sml2'        => { rom: 'roms/sml2.gb', warmup: 150_000, measured: 200_000,
                      nav: '0:start,300000:start,1000000:start,2000000:start,1500000:start,1500000:start' }
}.select { |_, p| File.exist?(p[:rom]) }

MODES = {
  'none' => [],
  'yjit' => ['--yjit'],
  'zjit' => ['--zjit']
}

File.open(OUT_CSV, 'w') do |csv|
  csv.puts 'profile,mode,rep,measured_steps,total_cycles,elapsed_seconds'

  PROFILES.each do |name, cfg|
    MODES.each do |mode, flags|
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      cmd = [RUBY, *flags, RUN_BATCH, cfg[:rom], cfg[:warmup].to_s, cfg[:measured].to_s, REPS.to_s,
             *[cfg[:nav]].compact]
      lines = IO.popen(cmd, &:readlines)
      raise "run_batch.rb failed for #{name}/#{mode}: #{$?.inspect}" unless $?.success?

      lines.each_with_index do |line, rep|
        jit, _rom, measured_steps, total_cycles, elapsed = line.strip.split(',')
        csv.puts [name, jit, rep, measured_steps, total_cycles, elapsed].join(',')
      end
      csv.flush
      warn "#{name}/#{mode}: #{lines.size} reps in #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round(1)}s"
    end
  end
end

puts "done -> #{OUT_CSV}"
