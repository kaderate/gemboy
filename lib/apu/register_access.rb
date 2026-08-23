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
    end

    def read_register(addr) = @registers.read(addr)
    def write_register(addr, value) = @registers.write(addr, value)

    def raw(addr) = @registers.raw(addr)
    def load(addr, value) = @registers.load(addr, value)
  end
end
