# ReadRegister is a micro-op that reads a value from a register and stores it in a temporary variable.
module MicroOperations
  class ReadRegister
    attr_reader :register

    def initialize(register)
      @register = register
    end

    def to_s
      "ReadRegister(#{@register})"
    end

    def execute(context)
      value = context.registers[@register]
      context.temp_variables[@register] = value
      { context:, nb_cycles: 0 }
    end
  end
end
