#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs every Blargg test ROM (test_roms/<suite>/**/*.gb) plus dmg-acid2.gb and cgb-acid2.gbc
# headlessly, and produces a self-contained report directory:
#
#   test_roms/report/index.html            - human-readable HTML report
#   test_roms/report/results.json          - structured results
#   test_roms/report/screenshots/<suite>/  - final framebuffer per ROM
#
# test_roms/homemade/ is intentionally excluded: it's a set of hand-written
# PPU ROMs, not a standard reference suite, and isn't meant to be tracked
# in this aggregated report.
#
# This script always exits 0 (informational report, no CI gating) but still
# prints a plain-text summary to stdout.
#
# Usage: ruby test_roms/run_all.rb

require 'erb'
require 'json'
require 'etc'
require 'fileutils'
require_relative 'support/rom_test_runner'

TEST_ROMS_DIR = __dir__
REPORT_DIR = File.join(TEST_ROMS_DIR, 'report')
SCREENSHOTS_DIR = File.join(REPORT_DIR, 'screenshots')

SUITES = %w[cpu_instrs dmg_sound halt_bug instr_timing interrupt_time mem_timing oam_bug].freeze

PARALLELISM = (ENV['TEST_ROMS_PARALLELISM'] || Etc.nprocessors).to_i.clamp(1, Etc.nprocessors)

# dmg-acid2/cgb-acid2 render a single static frame then loop forever waiting on
# vblank; 3s of emulated time is plenty to reach that frame.
MAX_T_CYCLES_OVERRIDES = { 'dmg-acid2' => 3 * CPU::T_CYCLES_PER_SECOND, 'cgb-acid2' => 3 * CPU::T_CYCLES_PER_SECOND }.freeze

# Suites reporting their result on screen only: the verdict comes from comparing the final
# framebuffer to a reference image rather than from the serial port.
REFERENCES = {
  'dmg-acid2' => File.join(TEST_ROMS_DIR, 'expected', 'dmg-acid2.png'),
  'cgb-acid2' => File.join(TEST_ROMS_DIR, 'expected', 'cgb-acid2.png')
}.freeze

def collect_roms
  roms = SUITES.each_with_object([]) do |suite, acc|
    suite_dir = File.join(TEST_ROMS_DIR, suite)
    Dir.glob(File.join(suite_dir, '**', '*.gb')).each do |rom_path|
      acc << { suite:, rom_path: }
    end
  end
  roms << { suite: 'dmg-acid2', rom_path: File.join(TEST_ROMS_DIR, 'dmg-acid2.gb') }
  roms << { suite: 'cgb-acid2', rom_path: File.join(TEST_ROMS_DIR, 'cgb-acid2.gbc') }
  roms
end

def execute_rom(suite, rom_path, screenshot_path)
  max_t_cycles = MAX_T_CYCLES_OVERRIDES[suite] || RomTestRunner::MAX_T_CYCLES
  result = RomTestRunner.run(rom_path, screenshot_path, max_t_cycles:, reference_path: REFERENCES[suite])
  [result.status, result.cycles, result.timed_out, result.serial, result.mismatch, nil]
rescue StandardError => e
  [:error, 0, false, '', nil, "#{e.class}: #{e.message}"]
end

def run_one(rom)
  name = File.basename(rom[:rom_path], '.gb')
  screenshot_dir = File.join(SCREENSHOTS_DIR, rom[:suite])
  FileUtils.mkdir_p(screenshot_dir)
  screenshot_path = File.join(screenshot_dir, "#{name}.png")

  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  status, cycles, timed_out, serial, mismatch, error = execute_rom(rom[:suite], rom[:rom_path], screenshot_path)
  duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

  {
    suite: rom[:suite],
    name:,
    status:,
    cycles:,
    timed_out:,
    serial:,
    mismatch:,
    error:,
    screenshot: File.join('screenshots', rom[:suite], "#{name}.png"),
    duration_seconds: duration.round(2)
  }
end

# Round-robin (rather than contiguous slices) so that suites with growing
# per-ROM duration (e.g. cpu_instrs) get spread across workers instead of
# piling their slowest ROMs onto a single one.
def partition_roms(roms)
  Array.new(PARALLELISM) { [] }.tap do |chunks|
    roms.each_with_index { |rom, i| chunks[i % PARALLELISM] << rom }
  end
end

def spawn_worker(chunk)
  reader, writer = IO.pipe
  pid = fork do
    reader.close
    chunk.each { |rom| Marshal.dump(run_one(rom), writer) }
    writer.close
  end
  writer.close
  [reader, pid]
end

def run_all(roms)
  readers, pids = partition_roms(roms).reject(&:empty?).map { |chunk| spawn_worker(chunk) }.transpose

  results = []
  pending = readers.dup
  until pending.empty?
    IO.select(pending).first.each do |io|
      if io.eof?
        pending.delete(io)
        io.close
        next
      end

      result = Marshal.load(io) # rubocop:disable Security/MarshalLoad -- own forked worker, not external input
      results << result
      puts "[#{result[:status]}] #{result[:suite]}/#{result[:name]} (#{result[:duration_seconds]}s)" \
           "#{" - #{result[:mismatch]} pixels off the reference" if result[:mismatch]&.positive?}" \
           "#{" - #{result[:error]}" if result[:error]}"
      $stdout.flush
    end
  end
  pids.each { |pid| Process.wait(pid) }
  results
end

def print_summary(results)
  puts "\n#{results.count { |r| r[:status] == :passed }} passed, " \
       "#{results.count { |r| r[:status] == :failed }} failed, " \
       "#{results.count { |r| r[:status] == :timeout }} timed out, " \
       "#{results.count { |r| r[:status] == :visual }} visual, " \
       "#{results.count { |r| r[:status] == :error }} error " \
       "(#{results.size} total, #{results.sum { |r| r[:duration_seconds] }.round(1)}s)"
end

FileUtils.mkdir_p(SCREENSHOTS_DIR)

results = run_all(collect_roms)

File.write(File.join(REPORT_DIR, 'results.json'), JSON.pretty_generate(results))

template = File.read(File.join(TEST_ROMS_DIR, 'support', 'report_template.html.erb'))
html = ERB.new(template).result_with_hash(results:)
File.write(File.join(REPORT_DIR, 'index.html'), html)

print_summary(results)
puts "\nReport: #{File.join(REPORT_DIR, 'index.html')}"
