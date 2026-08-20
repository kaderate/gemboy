# frozen_string_literal: true

require_relative 'constants'

module MBC
  # RTCRegisters represents the set of clock counter registers of an MBC3 cartridge
  class RTCRegisters
    REGISTERS_INDEXES = %i[rtc_s rtc_m rtc_h rtc_dl rtc_dh].freeze
    RTC_MASKS = [0x3F, 0x3F, 0x1F, 0xFF, 0xC1].freeze
    RTC_DH_DAY_MSB = 0x01
    RTC_DH_HALT    = 0x40
    RTC_DH_CARRY   = 0x80
    SECONDS_PER_DAY = 24 * 60 * 60
    DAY_COUNTER_SIZE = 512 # 9 bits: DH bit 0 + DL

    attr_reader :rtc_s, :rtc_m, :rtc_h, :rtc_dl, :rtc_dh

    def initialize(rtc_s, rtc_m, rtc_h, rtc_dl, rtc_dh)
      @rtc_s = rtc_s
      @rtc_m = rtc_m
      @rtc_h = rtc_h
      @rtc_dl = rtc_dl
      @rtc_dh = rtc_dh
    end

    def advance(seconds)
      return unless seconds.positive?

      days = ((rtc_dh & RTC_DH_DAY_MSB) << 8) | rtc_dl

      new_time = (days * SECONDS_PER_DAY) + (rtc_h * 60 * 60) + (rtc_m * 60) + rtc_s + seconds

      set_time_to_registers(new_time, day_counter_carry: new_time >= DAY_COUNTER_SIZE * SECONDS_PER_DAY)
    end

    def to_a
      [rtc_s, rtc_m, rtc_h, rtc_dl, rtc_dh]
    end

    def set_register(index, value)
      register = REGISTERS_INDEXES[index]
      instance_variable_set("@#{register}", value & RTC_MASKS[index])
    end

    def halted? = rtc_dh.anybits?(RTC_DH_HALT)

    private

    def set_time_to_registers(time, day_counter_carry: false)
      @rtc_s = time % 60
      @rtc_m = (time / 60) % 60
      @rtc_h = (time / 60 / 60) % 24
      nb_days = time / SECONDS_PER_DAY
      @rtc_dl = nb_days % 256

      dh_before = @rtc_dh
      dh_day_msb = (nb_days / 256) & 0x1
      day_counter_carry_bit = day_counter_carry ? RTC_DH_CARRY : (dh_before & RTC_DH_CARRY)
      @rtc_dh = (dh_before & RTC_DH_HALT) | dh_day_msb | day_counter_carry_bit
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
