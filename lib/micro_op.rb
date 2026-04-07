require_relative 'micro_operations'

# Describe a micro-op, which is a single operation that can be executed by the CPU.
class MicroOp
  attr_reader :name, :operations, :cpu, :logger

  def initialize(name, cpu, logger: nil)
    @name = name
    @cpu = cpu
    @logger = logger

    @operations = []
  end

  def read_register(register)
    @operations << MicroOperations::ReadRegister.new(register)
    self
  end

  def read_next_address
    @operations << MicroOperations::ReadNextAddress.new
    self
  end

  def jump_to_next_address
    @operations << MicroOperations::Jump.new(temp_variable: :next_address)
    self
  end

  def jump_to_address(address)
    @operations << MicroOperations::Jump.new(address:)
    self
  end

  def execute
    logger&.info "Executing #{name} @ 0x#{@cpu.pc.to_s(16)}"

    res = execute_operations
    copy_context_to_cpu(res[:new_context])

    res[:nb_cycles]
  end

  private

  def execute_operations
    context = Context.new(cpu.registers, cpu.pc, cpu.mmu)

    nb_cycles = @operations.sum do |operation|
      res = operation.execute(context)
      context = res[:context]
      res[:nb_cycles]
    end

    { new_context: context, nb_cycles: }
  end

  def copy_context_to_cpu(new_context)
    @cpu.registers = new_context.registers
    @cpu.pc = new_context.pc
  end

  class Context
    attr_accessor :registers, :pc, :mmu, :temp_variables

    def initialize(registers, pc, mmu)
      @registers = registers
      @pc = pc
      @mmu = mmu
      @temp_variables = {}
    end
  end
end
