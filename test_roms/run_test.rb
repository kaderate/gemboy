#!/usr/bin/env ruby
# frozen_string_literal: true

# CLI wrapper around RomTestRunner: runs a single ROM headlessly and prints
# a human-readable summary to stdout.
#
# Usage: ruby test_roms/run_test.rb <rom.gb> [output.png]

require_relative 'support/rom_test_runner'

rom_path = ARGV[0]
abort 'Usage: run_test.rb <rom.gb> [output.png]' unless rom_path

out_path = ARGV[1] || "#{File.basename(rom_path, '.gb')}.png"

result = RomTestRunner.run(rom_path, out_path)

puts "cycles: #{result.cycles} (#{(result.cycles / CPU::T_CYCLES_PER_SECOND).round(2)} seconds)"
puts "timed_out: #{result.timed_out}"
puts "serial: #{result.serial.empty? ? '(none)' : result.serial.inspect}"
puts "screenshot: #{result.screenshot}"
