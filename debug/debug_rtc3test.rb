# frozen_string_literal: true

# Runs one of the three rtc3test suites headlessly and screenshots the result.
#
# Usage: ruby debug/debug_rtc3test.rb [suite] [seconds] [symbols] [limiter]
#   limiter: run at 1x, required for anything the ROM times itself

require_relative 'headless_emulator'

SUITES = { basic: 0, range: 1, sub_second: 2 }.freeze

suite = (ARGV[0] || 'basic').to_sym
raise ArgumentError, "Unknown suite #{suite}, pick one of #{SUITES.keys.join(', ')}" unless SUITES.key?(suite)

seconds = (ARGV[1] || 45).to_i

input_sequence = [[:wait, 2, 'Boot to menu']]
SUITES[suite].times { input_sequence += [[:down, 0.3], [:wait, 0.3]] }
input_sequence += [[:a, 0.5, "Run #{suite} tests"], [:wait, seconds, 'Let the suite run']]

emulator = HeadlessEmulator.new(path: 'test_roms/rtc3test/rtc3test.gb', input_sequence:,
                                screenshot_format: ARGV.include?('symbols') ? :symbols : :image,
                                max_seconds: seconds + 15, with_limiter: ARGV.include?('limiter'))

exit emulator.start
