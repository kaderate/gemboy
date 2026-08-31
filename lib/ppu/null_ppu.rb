# frozen_string_literal: true

require_relative 'register_access'

class PPU
  # NullAPU is a dummy PPU to be used by the MMU unless the real one is initialized
  class NullPPU
    include RegisterAccess

    def read_cgb_register(_addr) = 0xFF
    def write_cgb_register(_addr, _value); end

    def on_read(_addr, read_value) = read_value
    def on_write(_addr, _value); end
    def on_load(_addr, _value); end

    def read_vram(_addr, _length = 1) = 0xFF

    def oam_reader
      Object.new.tap do |reader|
        def reader.read_oams = Array.new(40 * 4, 0xFF)
      end.freeze
    end

    # Standing in for #vram_bus/#oam_bus: reads 0xFF, writes go nowhere, either way.
    NULL_BUS = Object.new.tap do |bus|
      def bus.read(_addr) = 0xFF
      def bus.write(_addr, _value); end
      def bus.set_bank(_value); end
      def bus.bank_byte = 0xFF
    end.freeze

    def vram_bus = NULL_BUS
    def oam_bus = NULL_BUS
  end
end
