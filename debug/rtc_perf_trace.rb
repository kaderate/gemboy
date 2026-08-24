# frozen_string_literal: true

# Instruments MBC::RTC#update_rtc_registers! while the rtc3test sub_second suite runs headless,
# to check whether the RTC's own CPU cost is heavy enough to drift the real-time pacing that the
# ROM's sub-second timing tests rely on.
#
# Usage: ruby debug/rtc_perf_trace.rb [seconds] [threshold_ms]
#   threshold_ms: only log calls slower than this (default 0.5ms)

require_relative 'headless_emulator'
require_relative '../lib/mbc/rtc'

THRESHOLD_MS = (ARGV[1] || 0.5).to_f

module RTCPerfTrace
  Event = Struct.new(:host_ms, :cycles, :wall_ms, :seconds, :ripple_iterations, keyword_init: true)

  class << self
    attr_accessor :emulator

    def events = @events ||= []
    def call_count = @call_count ||= 0
    def total_wall_ms = @total_wall_ms ||= 0.0

    def install!(emulator)
      @emulator = emulator
      MBC::RTC.prepend(Instrumented)
      MBC::RTCRegisters.prepend(RippleCount)
    end

    def record(seconds, ripple_iterations, wall_ms)
      @call_count = call_count + 1
      @total_wall_ms = total_wall_ms + wall_ms
      return if wall_ms < THRESHOLD_MS

      events << Event.new(host_ms: (Time.now.to_f * 1000).to_i, cycles: emulator.total_cycle,
                          wall_ms: wall_ms.round(3), seconds:, ripple_iterations:)
    end

    def report
      puts format("\n%<count>d appels a update_rtc_registers!, %<total>.2fms cumules (%<avg>.4fms/appel en moyenne)",
                  count: call_count, total: total_wall_ms, avg: call_count.zero? ? 0 : total_wall_ms / call_count)
      puts "Appels > #{THRESHOLD_MS}ms (potentiels responsables d'une derive du pacing temps reel) :"
      if events.empty?
        puts '  aucun'
        return
      end
      puts '  host_ms      cycles       wall_ms    seconds    ripple_iterations'
      events.each do |e|
        puts format('  %<host>-12d %<cycles>-12d %<wall>-10.3f %<seconds>-10d %<ripple>s',
                    host: e.host_ms, cycles: e.cycles, wall: e.wall_ms, seconds: e.seconds, ripple: e.ripple_iterations)
      end
    end
  end

  module Instrumented
    def update_rtc_registers!
      before_cycles_acc = instance_variable_get(:@cycles_acc)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = super
      wall_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000

      seconds = before_cycles_acc / MBC::Constants::CYCLES_PER_SECOND
      rtc_registers = instance_variable_get(:@rtc_registers)
      RTCPerfTrace.record(seconds, rtc_registers.last_ripple_iterations, wall_ms)

      result
    end
  end

  # Wraps the ripple/bulk split to expose how many one-second-at-a-time steps the last #advance took.
  module RippleCount
    def advance_with_ripple_counters(seconds)
      remaining = super
      @last_ripple_iterations = seconds - remaining
      remaining
    end

    def last_ripple_iterations = @last_ripple_iterations || 0
  end
end

seconds = (ARGV[0] || 45).to_i

input_sequence = [[:wait, 2, 'Boot to menu'], [:down, 0.3], [:wait, 0.3], [:down, 0.3], [:wait, 0.3],
                  [:a, 0.5, 'Run sub_second tests'], [:wait, seconds, 'Let the suite run']]

emulator = HeadlessEmulator.new(path: 'test_roms/rtc3test/rtc3test.gb', input_sequence:,
                                screenshot_format: :symbols, max_seconds: seconds + 15, with_limiter: true)

RTCPerfTrace.install!(emulator)
emulator.start
RTCPerfTrace.report
