# frozen_string_literal: true

require_relative 'register_file'

class APU
  # The bus-facing side of the register file, shared by the real APU and the null one.
  # A module rather than a base class: APU is both this namespace and the concrete
  # implementation, so it cannot inherit from something nested inside itself.
  module RegisterAccess
    attr_accessor :registers

    def initialize
      @registers = RegisterFile.new
      @register_address_to_handler = {}
    end

    def load_registers = RegisterFile::RANGE.each { |addr| handler_for_addr(addr).on_load(addr, @registers.raw(addr)) }

    def read_register(addr)
      handler_for_addr(addr).on_read(addr, @registers.read(addr))
    end

    def write_register(addr, value)
      handler = handler_for_addr(addr)
      return unless handler.write_allowed?(addr)

      @registers.write(addr, value)
      handler.on_load(addr, value)
      handler.on_write(addr, value)
    end

    def raw(addr) = @registers.raw(addr)

    def load(addr, value)
      @registers.load(addr, value)
      handler_for_addr(addr).on_load(addr, value)
    end

    def set_default_handler(handler)
      @default_handler = handler
    end

    def set_register_address_to_handler(address:, handler:)
      @register_address_to_handler[address] = handler
    end

    private

    def handler_for_addr(addr) = @register_address_to_handler.fetch(addr, @default_handler)
  end
end
