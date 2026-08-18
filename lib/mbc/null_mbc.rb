# frozen_string_literal: true

require_relative 'external_ram'

module MBC
  # NullMBC is a memory bank controller that does the plain old ROM loading
  class NullMBC
    attr_reader :rom, :external_ram

    def initialize(cartridge)
      @rom = cartridge.rom_bytes

      @external_ram = ExternalRAM.new(bank_count: cartridge.cartridge_config.ram_bank_count,
                                      battery_path: cartridge.battery_ram_path)
      @external_ram.enabled = true
    end

    def read_rom(address) = @rom[address]
    def write_rom(_address, _value) = nil

    def read_ram(addr) = @external_ram.read(addr)
    def write_ram(addr, value) = @external_ram.write(addr, value)
    def save_battery_ram = @external_ram.save!
  end
end
