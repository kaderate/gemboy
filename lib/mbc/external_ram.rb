# frozen_string_literal: true

require_relative '../battery_ram'
require_relative '../edge_detector'
require_relative 'constants'

module MBC
  # External RAM is a banked memory that can be used to store data in a cartridge.
  class ExternalRAM
    attr_reader :bytes, :initial_rtc_config
    attr_accessor :bank

    def initialize(bank_count:, battery_path: nil, rtc_registers_provider: nil)
      @enabled = false
      @bank_count = bank_count
      @battery_path = battery_path
      @rtc_registers_provider = rtc_registers_provider # Provides the RTC registers to save, must respond to #rtc_data_to_save

      @bank = 0
      @enabled_edge = EdgeDetector.new

      battery_ram_config = BatteryRAM.load(@battery_path, ram_size: bank_count * Constants::RAM_BANK_SIZE) if with_battery?
      @initial_rtc_config = battery_ram_config&.rtc_config
      @bytes = battery_ram_config&.saved_ram || Array.new(Constants::RAM_BANK_SIZE * bank_count, 0xFF)
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
      turned_off = @enabled_edge.falling?(bool)
      @enabled = bool

      save! if with_battery? && turned_off
    end

    def save!
      BatteryRAM.save(@battery_path, @bytes, **rtc_data_to_save) if with_battery?
    end

    private

    def effective_bank_offset = (@bank % @bank_count) * Constants::RAM_BANK_SIZE
    def with_battery? = !@battery_path.nil?

    def rtc_data_to_save = @rtc_registers_provider&.rtc_data_to_save || {}
  end
end
