# frozen_string_literal: true

require_relative '../lib/mbc/rtc'

# Measures, for every RTC register write, how long the clock actually took to tick.
#
# The delay is reported twice: in host milliseconds (which is what the RTC is driven by) and in
# emulated milliseconds (which is what a test ROM measures with DIV/TIMA). Comparing the two tells
# whether a discrepancy comes from the clock itself or from the emulation speed.
module RTCTrace
  Event = Struct.new(:index, :millis, :expected, :host_delay, :emulated_delay, keyword_init: true)
  REGISTER_NAMES = %w[S M H DL DH].freeze
  ROW_FORMAT = '%<reg>-4s %<millis>8s %<expected>10s %<host>10s %<emulated>10s'
  # millis: how far into the current second the write landed; expected: what the ROM should therefore measure

  class << self
    attr_accessor :emulator

    def events = @events ||= []

    def install!(emulator)
      @emulator = emulator
      MBC::RTCRegisters.prepend(Registers)
      MBC::RTC.prepend(Clock)
    end

    def register_written(index, cycles_acc)
      @pending = { index:, cycles_acc:, host_ms: now_ms, cycles: emulator.total_cycle }
    end

    def ticked
      return unless @pending

      events << Event.new(index: @pending[:index], millis: to_ms(@pending[:cycles_acc]),
                          expected: to_ms(MBC::Constants::CYCLES_PER_SECOND - @pending[:cycles_acc]),
                          host_delay: now_ms - @pending[:host_ms],
                          emulated_delay: emulated_ms_since(@pending[:cycles]))
      @pending = nil
    end

    def report
      puts format(ROW_FORMAT, reg: 'REG', millis: 'millis', expected: 'expected', host: 'host', emulated: 'emulated')
      events.each do |event|
        puts format(ROW_FORMAT, reg: REGISTER_NAMES[event.index], millis: event.millis,
                                expected: "#{event.expected}ms", host: "#{event.host_delay}ms",
                                emulated: "#{event.emulated_delay}ms")
      end
    end

    private

    def now_ms = (Time.now.to_f * 1000).to_i
    def to_ms(cycles) = cycles * 1000 / MBC::Constants::CYCLES_PER_SECOND
    def emulated_ms_since(cycles) = ((emulator.total_cycle - cycles) * 1000 / CPU::T_CYCLES_PER_SECOND)
  end

  module Registers
    def advance(seconds)
      RTCTrace.ticked if seconds.positive?
      super
    end
  end

  module Clock
    def write_rtc_register(value)
      super
      RTCTrace.register_written(instance_variable_get(:@mapped_rtc_register), instance_variable_get(:@cycles_acc))
    end
  end
end
