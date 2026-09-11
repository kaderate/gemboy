# frozen_string_literal: true

# Orchestrates the YJIT vs ZJIT vs no-JIT comparison: for each (profile, mode) pair, spawns a
# single `run_batch.rb` process that boots ONCE (optionally navigating a menu first -- see
# run_one.rb's `nav` doc, PROFILES here doesn't use it by default), then fork()s `reps` children
# off that already-booted state to collect `reps` independent measurements (see run_batch.rb for
# why forking is still real isolation, not a shortcut).
#
# This intentionally trades the earlier "interleave every mode within every rep" ordering
# (which spread thermal/scheduler drift evenly across configurations) for wall-clock budget: a
# profile with menu navigation pays that cost once per (profile, mode) instead of once per rep.
# All reps of a given (profile, mode) now run back-to-back instead. Rerun with run_one.rb's
# per-process loop (still in this directory) if drift-order rigor matters more than wall time.
#
# Usage: ruby bench_yjit_vs_zjit.rb [reps] [out.csv]
#
# Needs a Ruby built with --enable-yjit --enable-zjit (neither the project's .ruby-version nor
# a plain rbenv install gives you --enable-zjit; build from source to get a --zjit mode here).
#
# RUBY env var overrides the interpreter binary used for the child processes (defaults to
# RbConfig.ruby, i.e. whichever `ruby` invoked this script).

require 'English'
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
PROFILES = {
  'cpu_instrs' => { rom: 'test_roms/cpu_instrs/cpu_instrs.gb', warmup: 150_000, measured: 200_000 },
  'dmg_sound' => { rom: 'test_roms/dmg_sound/dmg_sound.gb', warmup: 150_000, measured: 200_000 },
  'mem_timing' => { rom: 'test_roms/mem_timing/mem_timing.gb', warmup: 50_000, measured: 80_000 },
  'sprite_ppu' => { rom: 'test_roms/homemade/build/display_sprite_1.gb', warmup: 150_000, measured: 200_000 }
}.select { |_, p| File.exist?(p[:rom]) }

MODES = {
  'none' => [],
  'yjit' => ['--yjit'],
  'zjit' => ['--zjit']
}.freeze

File.open(OUT_CSV, 'w') do |csv|
  csv.puts 'profile,mode,rep,measured_steps,total_cycles,elapsed_seconds'

  PROFILES.each do |name, cfg|
    MODES.each do |mode, flags|
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      cmd = [RUBY, *flags, RUN_BATCH, cfg[:rom], cfg[:warmup].to_s, cfg[:measured].to_s, REPS.to_s,
             *[cfg[:nav]].compact]
      lines = IO.popen(cmd, &:readlines)
      raise "run_batch.rb failed for #{name}/#{mode}: #{$CHILD_STATUS.inspect}" unless $CHILD_STATUS.success?

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
