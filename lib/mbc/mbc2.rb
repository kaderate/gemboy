# frozen_string_literal: true

require_relative 'constants'
require_relative 'base_mbc'
require_relative '../battery_ram'

module MBC
  # MBC2 has a single combined register: bit 8 of the write address (not the value) picks between RAM enable and ROM bank select.
  # Its RAM is 512x4 bits built into the MBC2 chip itself. Only 0x0000-0x3FFF is wired.
  class MBC2 < BaseMBC
    BANK_SIZE = Constants::ROM_BANK_SIZE
    BANK_START = Constants::ROM_BANK_START
    RAM_SIZE = 512
    RAM_ENABLE_VALUE = 0x0A

    ROM_AREAS = Array.new(256).tap do |arr|
      (0x00..0x3F).each { |i| arr[i] = i.even? ? :ram_bank_enable : :bank_select }
    end.freeze

    attr_reader :rom

    def initialize(cartridge, external_ram_start: 0xA000)
      super(external_ram_start:)
      @rom = cartridge.rom_bytes
      @rom_bank_count = cartridge.cartridge_config.rom_bank_count

      @active_bank = 1
      @ram_enabled = false
      @battery_path = cartridge.battery_ram_path
      @ram = load_ram
    end

    def read_rom(addr)
      if addr < BANK_START
        @rom[addr]
      else
        bank_addr = ((@active_bank % @rom_bank_count) * BANK_SIZE) + (addr - BANK_START)
        @rom[bank_addr]
      end
    end

    def write_rom(addr, value)
      case ROM_AREAS[addr >> 8]
      when :bank_select
        @active_bank = value & 0x0F
        @active_bank = 1 if @active_bank.zero? # same quirk as MBC1
      when :ram_bank_enable
        @ram_enabled = (value & 0x0F) == RAM_ENABLE_VALUE
      end
    end

    def read_ram(addr)
      return 0xFF unless @ram_enabled

      0xF0 | @ram[addr % RAM_SIZE]
    end

    def write_ram(addr, value)
      return unless @ram_enabled

      @ram[addr % RAM_SIZE] = value & 0x0F
    end

    def save_battery_ram
      BatteryRAM.save(@battery_path, @ram) if @battery_path
    end

    private

    def load_ram
      return Array.new(RAM_SIZE, 0xFF) unless @battery_path

      BatteryRAM.load(@battery_path, ram_size: RAM_SIZE).saved_ram || Array.new(RAM_SIZE, 0xFF)
    end
  end
end
