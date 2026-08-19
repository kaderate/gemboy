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

    attr_reader :rom, :external_ram

    def initialize(cartridge)
      @rom = cartridge.rom_bytes

      # Internal state
      @rom_bank_count = cartridge.cartridge_config.rom_bank_count
      @active_bank = 1
      @mapped_rtc_register = -1
      @prev_latch_register = -1

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
        @latched_rtc_registers = @rtc_registers.dup if @prev_latch_register == 0x0 && value == 0x01
        @prev_latch_register = value
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
    def fetch_rtc_data = { rtc_registers: @rtc_registers, rtc_latched_registers: @latched_rtc_registers }

    private

    def initialize_rtc
      # delta_since_save_in_sec = Time.now.to_i - @external_ram.rtc_unix_timestamp
      # TODO: Add delta_since_save_in_sec to the time stored in @rtc_registers
      rtc_config = @external_ram.initial_rtc_config || {}
      @rtc_registers = rtc_config[:rtc_registers] || [59, 59, 12, 0x00, 0x00]
      @latched_rtc_registers = rtc_config[:rtc_latched_registers] || [59, 59, 12, 0x00, 0x00]
    end

    def write_rtc_register(value)
      # Not sure I need to check values overflow...
      # Could be a: @rtc_registers[@latch_register] = value
      case @mapped_rtc_register
      when 0, 1 then @rtc_registers[@mapped_rtc_register] = value > 0x3B ? 0x3B : value # rubocop:disable Style/MinMaxComparison
      when 2 then @rtc_registers[2] = value > 0x17 ? 0x17 : value # rubocop:disable Style/MinMaxComparison
      when 3 then @rtc_registers[3] = value
      when 4 then @rtc_registers[4] = value
      end
    end
  end
end
