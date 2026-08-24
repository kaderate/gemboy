# frozen_string_literal: true

# Runs the rtc3test sub_second suite headless with RTCTrace installed, to see -- for every RTC
# register write -- how long it actually took the seconds register to tick afterwards, in both
# host time (what drives the RTC) and emulated time (what the ROM measures via DIV/TIMA).
#
# Usage: ruby debug/rtc_write_tick_trace.rb [seconds]

require_relative 'headless_emulator'
require_relative 'rtc_trace'

seconds = (ARGV[0] || 45).to_i

input_sequence = [[:wait, 2, 'Boot to menu'], [:down, 0.3], [:wait, 0.3], [:down, 0.3], [:wait, 0.3],
                  [:a, 0.5, 'Run sub_second tests'], [:wait, seconds, 'Let the suite run']]

emulator = HeadlessEmulator.new(path: 'test_roms/rtc3test/rtc3test.gb', input_sequence:,
                                screenshot_format: :symbols, max_seconds: seconds + 15, with_limiter: true)

RTCTrace.install!(emulator)
emulator.start
RTCTrace.report
