# frozen_string_literal: true

require_relative 'boot_values'
require_relative 'mmu'

class CPU
  # ...

  def build_opcodes
    @opcode_handlers = OPCODE_DISPATCH.map { |sym| __send__(sym) }.freeze
  end
