# frozen_string_literal: true

require_relative 'external_ram'
require_relative 'constants'
require_relative 'rtc'
require_relative 'base_mbc'

module MBC
  # MBC3 is a memory bank controller that supports up to 128 ROM banks and up to 4 RAM banks.
  # It is a variation of MBC5 that adds support for a built-in real time clock.
  class MBC3 < BaseMBC
    ROM_AREAS = Array.new(256).tap do |arr|
      arr.fill(:ram_bank_enable, 0x00..0x1F)
      arr.fill(:bank_select, 0x20..0x3F)
      arr.fill(:ram_bank_select_or_rtc, 0x40..0x5F)
      arr.fill(:latch_clock_data, 0x60..0x7F)
    end.freeze

    attr_reader :rom, :external_ram, :rtc

    def initialize(cartridge, external_ram_start: 0xA000)
      super(external_ram_start:)
      @rom = cartridge.rom_bytes

      # Internal state
      @rom_bank_count = cartridge.cartridge_config.rom_bank_count
      @active_bank = 1

      @external_ram = ExternalRAM.new(bank_count: cartridge.cartridge_config.ram_bank_count,
                                      battery_path: cartridge.battery_ram_path,
                                      rtc_registers_provider: self)

      initialize_rtc(cartridge.cartridge_config.with_timer?)
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
          @rtc.mapped_rtc_register = -1 # The RAM bank takes the window back
        elsif value <= 0x0C
          @rtc.mapped_rtc_register = value - 0x08
        end
      when :latch_clock_data
        @rtc.latch!(value)
      end
    end

    def read_ram(addr)
      return @rtc.read_rtc_registers if @rtc.registers_mapped?

      @external_ram.read(addr - @external_ram_start)
    end

    def write_ram(addr, value)
      return @rtc.write_rtc_register(value) if @rtc.registers_mapped?

      @external_ram.write(addr - @external_ram_start, value)
    end

    def save_battery_ram = @external_ram.save!

    # All save paths goes here so the registers are refreshed before being written
    def rtc_data_to_save
      @rtc.rtc_data_to_save
    end

    private

    def initialize_rtc(timer_enabled)
      @rtc = timer_enabled ? RTC.new(@external_ram.initial_rtc_config) : NullRTC.new
    end
  end
end
