# frozen_string_literal: true

require_relative 'external_ram'
require_relative 'constants'
require_relative 'base_mbc'

module MBC
  # MBC1 is a memory bank controller that supports up to 2MB of ROM and up to 1MB of RAM
  class MBC1 < BaseMBC
    BANK_SIZE = Constants::ROM_BANK_SIZE
    BANK_START = Constants::ROM_BANK_START

    ROM_AREAS = Array.new(256).tap do |arr|
      arr.fill(:ram_bank_enable, 0x00..0x1F)
      arr.fill(:bank_select, 0x20..0x3F)
      arr.fill(:bank_select_secondary, 0x40..0x5F)
      arr.fill(:banking_mode, 0x60..0x7F)
    end.freeze

    attr_reader :rom, :external_ram

    def initialize(cartridge, external_ram_start: 0xA000)
      super(external_ram_start:)
      @rom = cartridge.rom_bytes

      # Internal state
      @rom_bank_count = cartridge.cartridge_config.rom_bank_count
      @active_bank = 1
      @secondary_bank = 0
      @banking_mode = 0

      @external_ram = ExternalRAM.new(bank_count: cartridge.cartridge_config.ram_bank_count,
                                      battery_path: cartridge.battery_ram_path)
    end

    def read_rom(addr)
      if addr < BANK_START
        if @banking_mode == 1
          bank = (@secondary_bank << 5) % @rom_bank_count
          addr += (bank * BANK_SIZE)
        end
        @rom[addr]
      else
        effective_bank = (@active_bank | (@secondary_bank << 5)) % @rom_bank_count
        bank_addr = (effective_bank * BANK_SIZE) + (addr - BANK_START)
        @rom[bank_addr]
      end
    end

    def write_rom(addr, value)
      case ROM_AREAS[addr >> 8]
      when :bank_select
        @active_bank = value & 0x1F
        @active_bank = 1 if @active_bank.zero? # MBC1 quirk
      when :ram_bank_enable
        enabled = (value & 0xF) == 0xA # 0xA = special value to enable RAM
        @external_ram.enabled = enabled
      when :bank_select_secondary
        @secondary_bank = value & 0x3
        update_external_ram_bank
      when :banking_mode
        @banking_mode = value & 0x1
        update_external_ram_bank
      end
    end

    def read_ram(addr) = @external_ram.read(addr - @external_ram_start)
    def write_ram(addr, value) = @external_ram.write(addr - @external_ram_start, value)
    def save_battery_ram = @external_ram.save!

    private

    def update_external_ram_bank
      @external_ram.bank = @banking_mode == 1 ? @secondary_bank : 0
    end
  end
end
