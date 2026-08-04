#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs every Blargg test ROM (test_roms/<suite>/**/*.gb) plus dmg-acid2.gb
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
require 'fileutils'
require_relative 'support/rom_test_runner'

TEST_ROMS_DIR = __dir__
REPORT_DIR = File.join(TEST_ROMS_DIR, 'report')
SCREENSHOTS_DIR = File.join(REPORT_DIR, 'screenshots')

SUITES = %w[cpu_instrs dmg_sound halt_bug instr_timing interrupt_time mem_timing oam_bug].freeze

def collect_roms
  roms = SUITES.each_with_object([]) do |suite, acc|
    suite_dir = File.join(TEST_ROMS_DIR, suite)
    Dir.glob(File.join(suite_dir, '**', '*.gb')).sort.each do |rom_path|
      acc << { suite:, rom_path: }
    end
  end
  roms << { suite: 'dmg-acid2', rom_path: File.join(TEST_ROMS_DIR, 'dmg-acid2.gb') }
  roms
end

def run_one(rom)
  name = File.basename(rom[:rom_path], '.gb')
  screenshot_dir = File.join(SCREENSHOTS_DIR, rom[:suite])
  FileUtils.mkdir_p(screenshot_dir)
  screenshot_path = File.join(screenshot_dir, "#{name}.png")

  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  begin
    result = RomTestRunner.run(rom[:rom_path], screenshot_path)
    status = result.status
    cycles = result.cycles
    timed_out = result.timed_out
    serial = result.serial
    error = nil
  rescue StandardError => e
    status = :error
    cycles = 0
    timed_out = false
    serial = ''
    error = "#{e.class}: #{e.message}"
  end
  duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

  {
    suite: rom[:suite],
    name:,
    status:,
    cycles:,
    timed_out:,
    serial:,
    error:,
    screenshot: File.join('screenshots', rom[:suite], "#{name}.png"),
    duration_seconds: duration.round(2)
  }
end

def run_all(roms)
  roms.map do |rom|
    result = run_one(rom)
    puts "[#{result[:status]}] #{result[:suite]}/#{result[:name]} (#{result[:duration_seconds]}s)" \
         "#{" - #{result[:error]}" if result[:error]}"
    $stdout.flush
    result
  end
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
