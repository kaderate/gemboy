# frozen_string_literal: true

require_relative 'register_file'

class PPU
  # The bus-facing side of the register file
  module RegisterAccess
    attr_accessor :registers

    def initialize
      @registers = RegisterFile.new
      @default_handler = self
    end

    def load_registers = RegisterFile::RANGE.each { |addr| @default_handler.on_load(addr, @registers.raw(addr)) }

    def read_register(addr)
      @default_handler.on_read(addr, @registers.read(addr))
    end

    def write_register(addr, value)
      @registers.write(addr, value)
      @default_handler.on_load(addr, value)
      @default_handler.on_write(addr, value)
    end

    def raw(addr) = @registers.raw(addr)

    def load(addr, value)
      @registers.load(addr, value)
      @default_handler.on_load(addr, value)
    end
  end
end
