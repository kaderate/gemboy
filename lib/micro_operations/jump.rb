# Jump is a micro operation that sets the program counter (PC) to a new address.
module MicroOperations
  class Jump
    attr_reader :address

    def initialize(address: nil, temp_variable: nil)
      @address = address
      @temp_variable = temp_variable

      raise ArgumentError, "address xor temp_variable required" unless @address.nil? ^ @temp_variable.nil?
    end

    def to_s
      "Jump(#{address_to_jump})"
    end

    def execute(context)
      context.pc = address_to_jump(context)
      { context:, nb_cycles: 0 }
    end

    private

    def address_to_jump(context)
      @address_to_jump ||= address || temp_variable_value(context)
    end

    def temp_variable_value(context)
      context.temp_variables[@temp_variable] || raise("Temp variable #{@temp_variable} not found in context")
    end
  end
end
