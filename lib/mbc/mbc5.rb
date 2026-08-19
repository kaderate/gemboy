# frozen_string_literal: true

require_relative 'external_ram'
require_relative 'constants'

module MBC
  # MBC5 is a memory bank controller that supports up to 512 banks of ROM and up to 16 banks of RAM.
  class MBC5
    ROM_AREAS = Array.new(256).tap do |arr|
      arr.fill(:ram_bank_enable, 0x00..0x1F)
      arr.fill(:bank_select_low, 0x20..0x2F)
      arr.fill(:bank_select_high, 0x30..0x3F)
      arr.fill(:ram_bank_select, 0x40..0x5F)
    end.freeze

    attr_reader :rom, :external_ram

    def initialize(cartridge)
      @rom = cartridge.rom_bytes

      # Internal state
      @rom_bank_count = cartridge.cartridge_config.rom_bank_count
      @active_bank = 1

      @external_ram = ExternalRAM.new(bank_count: cartridge.cartridge_config.ram_bank_count,
                                      battery_path: cartridge.battery_ram_path)
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
      when :ram_bank_enable
        enabled = (value & 0xF) == 0xA # 0xA = special value to enable RAM
        @external_ram.enabled = enabled
      when :bank_select_low
        @active_bank = (@active_bank & 0x100) | value
      when :bank_select_high
        @active_bank = (@active_bank & 0xFF) | ((value & 0x1) << 8)
      when :ram_bank_select
        @external_ram.bank = value & 0xF
      end
    end

    def read_ram(addr) = @external_ram.read(addr)
    def write_ram(addr, value) = @external_ram.write(addr, value)
    def save_battery_ram = @external_ram.save!
  end
end
