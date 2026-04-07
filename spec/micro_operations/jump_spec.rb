require_relative '../../lib/micro_operations'
require_relative '../../lib/cpu'
require_relative '../../lib/mmu'

RSpec.describe MicroOperations::Jump do
  it "sets PC to direct address" do
    mmu = MMU.new(Array.new(0x8000, 0x00))
    registers = { a: 0x00, b: 0x00, c: 0x00, d: 0x00, e: 0x00, h: 0x00, l: 0x00, f: 0x00 }
    context = MicroOp::Context.new(registers, 0x0100, mmu)

    operation = MicroOperations::Jump.new(address: 0x0200)
    result = operation.execute(context)

    expect(result[:context].pc).to eq(0x0200)
  end

  it "sets PC from temp_variable" do
    mmu = MMU.new(Array.new(0x8000, 0x00))
    registers = { a: 0x00, b: 0x00, c: 0x00, d: 0x00, e: 0x00, h: 0x00, l: 0x00, f: 0x00 }
    context = MicroOp::Context.new(registers, 0x0100, mmu)
    context.temp_variables[:next_address] = 0x0300

    operation = MicroOperations::Jump.new(temp_variable: :next_address)
    result = operation.execute(context)

    expect(result[:context].pc).to eq(0x0300)
  end

  it "returns 0 cycles" do
    mmu = MMU.new(Array.new(0x8000, 0x00))
    registers = { a: 0x00, b: 0x00, c: 0x00, d: 0x00, e: 0x00, h: 0x00, l: 0x00, f: 0x00 }
    context = MicroOp::Context.new(registers, 0x0100, mmu)

    operation = MicroOperations::Jump.new(address: 0x0200)
    result = operation.execute(context)

    expect(result[:nb_cycles]).to eq(0)
  end

  it "requires either address or temp_variable (XOR validation)" do
    expect { MicroOperations::Jump.new }.to raise_error(ArgumentError)
    expect { MicroOperations::Jump.new(address: 0x100, temp_variable: :next_address) }.to raise_error(ArgumentError)
  end

  it "raises error if temp_variable not found in context" do
    mmu = MMU.new(Array.new(0x8000, 0x00))
    registers = { a: 0x00, b: 0x00, c: 0x00, d: 0x00, e: 0x00, h: 0x00, l: 0x00, f: 0x00 }
    context = MicroOp::Context.new(registers, 0x0100, mmu)

    operation = MicroOperations::Jump.new(temp_variable: :missing)
    expect { operation.execute(context) }.to raise_error('Temp variable missing not found in context')
  end
end
