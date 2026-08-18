# frozen_string_literal: true

require_relative '../battery_ram'

module MBC
  # External RAM is a banked memory that can be used to store data in a cartridge.
  class ExternalRAM
    BANK_SIZE = 0x2000

    attr_reader :bytes
    attr_accessor :bank

    def initialize(bank_count:, battery_path: nil)
      @enabled = false
      @bank_count = bank_count
      @battery_path = battery_path
      @bank = 0

      @bytes = (with_battery? && BatteryRAM.load(@battery_path).saved_ram) || Array.new(@bank_count * BANK_SIZE, 0)
    end

    def read(addr)
      return 0xFF unless @enabled && @bank_count.positive?

      @bytes[addr + effective_bank_offset] || 0xFF
    end

    def write(addr, value)
      return unless @enabled && @bank_count.positive?

      @bytes[addr + effective_bank_offset] = value
    end

    def enabled=(bool)
      prev_value = @enabled
      @enabled = bool

      save! if with_battery? && !@enabled && prev_value
    end

    def save!
      BatteryRAM.save(@battery_path, @bytes) if with_battery?
    end

    private

    def effective_bank_offset = (@bank % @bank_count) * BANK_SIZE
    def with_battery? = !@battery_path.nil?
  end
end
