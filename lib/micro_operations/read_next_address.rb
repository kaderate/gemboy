# ReadNextAddress is a micro-operation that reads the next byte from memory at the PC and stores it in a temporary variable.
module MicroOperations
  class ReadNextAddress
    def to_s
      "ReadNextAddress"
    end

    def execute(context)
      value = context.mmu.read_16(context.pc + 1) # Read the next 2 bytes after the opcode
      context.temp_variables[:next_address] = value
      { context:, nb_cycles: 8 }
    end
  end
end
