# frozen_string_literal: true

module MicroOperations
  # Stop handles the STOP opcode
  class Stop
    def to_s
      'Stop'
    end

    def execute(context)
      context.halted = { value: true, stopped: true }
      context.pc += 2 # STOP is a 2-bytes instruction
      { context:, nb_cycles: 0 }
    end
  end
end
