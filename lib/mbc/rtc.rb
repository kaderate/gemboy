# frozen_string_literal: true

require_relative 'constants'

module MBC
  # RTCRegisters represents the set of clock counter registers of an MBC3 cartridge
  class RTCRegisters
    class RippleCounter
      attr_accessor :value

      def initialize(value: 0, bit_width: 6, thresold: 59)
        @value = value
        @width = 2**bit_width
        @thresold = thresold
      end

      def tick
        if @value == @thresold
          @value = 0
          true
        else
          @value = (@value + 1) % @width
          false
        end
      end

      def off_limit?
        @value > @thresold
      end
    end

    REGISTERS_INDEXES = %i[rtc_s rtc_m rtc_h rtc_dl rtc_dh].freeze
    RTC_MASKS = [0x3F, 0x3F, 0x1F, 0xFF, 0xC1].freeze
    RTC_DH_DAY_MSB = 0x01
    RTC_DH_HALT    = 0x40
    RTC_DH_CARRY   = 0x80
    HOURS = 3600      # seconds
    DAYS = 24 * HOURS # seconds
    DAY_COUNTER_SIZE = 512 # 9 bits: DH bit 0 + DL

    def initialize(rtc_s, rtc_m, rtc_h, rtc_dl, rtc_dh)
      @rtc_sec = RippleCounter.new(value: rtc_s)
      @rtc_min = RippleCounter.new(value: rtc_m)
      @rtc_hour = RippleCounter.new(value: rtc_h, bit_width: 5, thresold: 23)
      nb_days = (rtc_dl + ((rtc_dh & RTC_DH_DAY_MSB) * 256))
      @rtc_day = RippleCounter.new(value: nb_days, bit_width: 9, thresold: DAY_COUNTER_SIZE - 1)

      @counters = [@rtc_sec, @rtc_min, @rtc_hour, @rtc_day]

      @halt = rtc_dh.anybits?(RTC_DH_HALT)
      @day_carry = rtc_dh.anybits?(RTC_DH_CARRY)
    end

    def advance(seconds)
      return unless seconds.positive?

      remaining_seconds = advance_with_ripple_counters(seconds)
      advance_with_seconds(remaining_seconds) if remaining_seconds.positive?
    end

    def advance_with_ripple_counters(seconds)
      remaining_seconds = seconds

      while ripple_counters_off_limit? && remaining_seconds.positive?
        carry = @rtc_sec.tick
        carry = @rtc_min.tick if carry
        carry = @rtc_hour.tick if carry
        new_day_carry = @rtc_day.tick if carry
        @day_carry = true if new_day_carry

        remaining_seconds -= 1
      end

      remaining_seconds
    end

    def advance_with_seconds(seconds)
      new_time = (@rtc_day.value * DAYS) + (@rtc_hour.value * HOURS) + (@rtc_min.value * 60) + @rtc_sec.value + seconds

      @rtc_sec.value = new_time % 60
      @rtc_min.value = (new_time / 60) % 60
      @rtc_hour.value = (new_time / HOURS) % 24
      @rtc_day.value = (new_time / DAYS) % DAY_COUNTER_SIZE
      @day_carry = true if new_time >= DAY_COUNTER_SIZE * DAYS
    end

    def to_a
      [rtc_s, rtc_m, rtc_h, rtc_dl, rtc_dh]
    end

    def set_register(index, value)
      case REGISTERS_INDEXES[index]
      when :rtc_s
        @rtc_sec.value = (value & RTC_MASKS[index])
      when :rtc_m
        @rtc_min.value = (value & RTC_MASKS[index])
      when :rtc_h
        @rtc_hour.value = (value & RTC_MASKS[index])
      when :rtc_dl
        @rtc_day.value = (@rtc_day.value & ~RTC_MASKS[index]) | (value & RTC_MASKS[index])
      when :rtc_dh
        day_msb = value & RTC_DH_DAY_MSB
        @rtc_day.value = (@rtc_day.value & 0xFF) | (day_msb << 8)
        @halt = value.anybits?(RTC_DH_HALT)
        @day_carry = value.anybits?(RTC_DH_CARRY)
      else
        raise "Unknown register index #{index}"
      end
    end

    def ripple_counters_off_limit? = @counters.any?(&:off_limit?)
    def halted? = @halt
    def rtc_s = @rtc_sec.value
    def rtc_m = @rtc_min.value
    def rtc_h = @rtc_hour.value
    def rtc_dl = @rtc_day.value % 256

    def rtc_dh
      dh_halt = @halt ? RTC_DH_HALT : 0
      dh_day_msb = (@rtc_day.value / 256) & 0x1
      day_counter_carry_bit = @day_carry ? RTC_DH_CARRY : 0
      (dh_halt | dh_day_msb | day_counter_carry_bit)
    end
  end

  # RTC is the real time clock of an MBC3 cartridge
  class RTC
    DEFAULT_REGISTERS = [59, 59, 12, 0x00, 0x00].freeze

    attr_writer :mapped_rtc_register

    def initialize(rtc_config)
      @mapped_rtc_register = -1
      @prev_latch_write = -1
      @cycles_acc = 0

      rtc_config ||= {}
      @latched_rtc_registers = rtc_config[:rtc_latched_registers] || DEFAULT_REGISTERS.dup
      @rtc_registers = RTCRegisters.new(*(rtc_config[:rtc_registers] || DEFAULT_REGISTERS))
      catch_up_rtc_registers_from_saved_time(rtc_config[:rtc_unix_timestamp])
    end

    def latch!(value)
      return unless @prev_latch_write == 0x0 && value == 0x01

      update_rtc_registers!
      @latched_rtc_registers = @rtc_registers.to_a
    ensure
      @prev_latch_write = value
    end

    def tick!(nb_cycles)
      @cycles_acc += nb_cycles
    end

    def write_rtc_register(value)
      # Catch up before writing, so the clock stops exactly when halt is set and the game's value always wins.
      update_rtc_registers!
      @cycles_acc = 0 if @mapped_rtc_register == RTCRegisters::REGISTERS_INDEXES.index(:rtc_s)
      @rtc_registers.set_register(@mapped_rtc_register, value)
    end

    def rtc_data_to_save
      update_rtc_registers!
      { rtc_registers: @rtc_registers.to_a, rtc_latched_registers: @latched_rtc_registers }
    end

    def registers_mapped? = @mapped_rtc_register >= 0
    def read_rtc_registers = @latched_rtc_registers[@mapped_rtc_register]

    private

    def update_rtc_registers!
      elapsed_seconds = refresh_cycles_acc!

      return if halted?

      @rtc_registers.advance(elapsed_seconds)
    end

    def refresh_cycles_acc!
      elapsed_seconds, @cycles_acc = @cycles_acc.divmod(Constants::CYCLES_PER_SECOND)
      elapsed_seconds
    end

    def catch_up_rtc_registers_from_saved_time(saved_time)
      return unless !halted? && saved_time

      delta_since_last_save = (Time.now.to_i - saved_time)
      @rtc_registers.advance(delta_since_last_save)
    end

    def halted? = @rtc_registers.halted?
  end

  # NullRTC is used when no RTC is present in the cartridge
  class NullRTC
    def tick!(_nb_cycles) = nil
    def latch!(_value) = nil
    def write_rtc_register(_value) = nil
    def registers_mapped? = false
    def read_rtc_registers = 0x0
    def rtc_data_to_save = {}
    def mapped_rtc_register=(_value); end
  end
end
