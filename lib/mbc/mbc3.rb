# frozen_string_literal: true

require_relative 'external_ram'
require_relative 'constants'

module MBC
  # MBC3 is a memory bank controller that supports up to 128 ROM banks and up to 4 RAM banks.
  # It is a variation of MBC5 that adds support for a built-in real time clock.
  class MBC3
    ROM_AREAS = Array.new(256).tap do |arr|
      arr.fill(:ram_bank_enable, 0x00..0x1F)
      arr.fill(:bank_select, 0x20..0x3F)
      arr.fill(:ram_bank_select_or_rtc, 0x40..0x5F)
      arr.fill(:latch_clock_data, 0x60..0x7F)
    end.freeze
    RTC_DH_DAY_MSB = 0x01
    RTC_DH_HALT    = 0x40
    RTC_DH_CARRY   = 0x80

    attr_reader :rom, :external_ram

    def initialize(cartridge)
      @rom = cartridge.rom_bytes

      # Internal state
      @rom_bank_count = cartridge.cartridge_config.rom_bank_count
      @active_bank = 1
      @mapped_rtc_register = -1
      @prev_latch_write = -1

      @external_ram = ExternalRAM.new(bank_count: cartridge.cartridge_config.ram_bank_count,
                                      battery_path: cartridge.battery_ram_path,
                                      rtc_registers_provider: self)

      initialize_rtc
    end

    def read_rom(addr)
      if addr < Constants::ROM_BANK_START
        @rom[addr]
      else
        effective_bank = @active_bank % @rom_bank_count
        bank_addr = (effective_bank * Constants::ROM_BANK_SIZE) + (addr - Constants::ROM_BANK_START)
        @rom[bank_addr]
      end
    end

    def write_rom(addr, value)
      case ROM_AREAS[addr >> 8]
      when :bank_select
        @active_bank = value & 0x7F
        @active_bank = 1 if @active_bank.zero? # MBC1 quirk
      when :ram_bank_enable
        enabled = (value & 0xF) == 0xA # 0xA = special value to enable RAM
        @external_ram.enabled = enabled
      when :ram_bank_select_or_rtc
        if value < 0x08
          @external_ram.bank = value
          @mapped_rtc_register = -1 # The RAM bank takes the window back
        elsif value <= 0x0C
          @mapped_rtc_register = value - 0x08
        end
      when :latch_clock_data
        latch!(value)
        @prev_latch_write = value
      end
    end

    def read_ram(addr)
      return @latched_rtc_registers[@mapped_rtc_register] if @mapped_rtc_register >= 0

      @external_ram.read(addr)
    end

    def write_ram(addr, value)
      return write_rtc_register(value) if @mapped_rtc_register >= 0

      @external_ram.write(addr, value)
    end

    def save_battery_ram = @external_ram.save!

    # All save paths goes here so the registers are refreshed before being written
    def fetch_rtc_data
      update_rtc_registers!
      { rtc_registers: @rtc_registers.to_a, rtc_latched_registers: @latched_rtc_registers }
    end

    private

    def latch!(value)
      return unless @prev_latch_write == 0x0 && value == 0x01

      update_rtc_registers!
      @latched_rtc_registers = @rtc_registers.to_a
    end

    # The clock is never ticked but recomputed from the host time when needed (on latch, register write or save)
    def update_rtc_registers!
      return if halted?

      Time.now.to_i.tap do |now|
        seconds_since_last_update = now - @last_rtc_registers_write
        @rtc_registers.advance(seconds_since_last_update)
        @last_rtc_registers_write = now
      end
    end

    def initialize_rtc
      rtc_config = @external_ram.initial_rtc_config || {}
      @latched_rtc_registers = rtc_config[:rtc_latched_registers] || [59, 59, 12, 0x00, 0x00]

      @rtc_registers = RTCRegisters.new(*rtc_config[:rtc_registers] || [59, 59, 12, 0x00, 0x00])
      @last_rtc_registers_write = Time.at(rtc_config[:rtc_unix_timestamp] || Time.now.to_i).to_i
      update_rtc_registers!
    end

    def write_rtc_register(value)
      # Catch up before writing, so the clock stops exactly when halt is set and the game's value always wins.
      update_rtc_registers!
      @rtc_registers.set_register(@mapped_rtc_register, value)
      @last_rtc_registers_write = Time.now.to_i
    end

    def halted? = @rtc_registers.rtc_dh & RTC_DH_HALT > 0

    class RTCRegisters
      REGISTERS_INDEXES = %i[rtc_s rtc_m rtc_h rtc_dl rtc_dh].freeze
      RTC_MASKS = [0x3F, 0x3F, 0x1F, 0xFF, 0xC1].freeze
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
  end
end
