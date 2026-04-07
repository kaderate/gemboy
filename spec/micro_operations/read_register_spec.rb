require_relative '../../lib/micro_operations'
require_relative '../../lib/cpu'
require_relative '../../lib/mmu'

RSpec.describe MicroOperations::ReadRegister do
  it "reads value from register and stores in temp_variables" do
    mmu = MMU.new(Array.new(0x8000, 0x00))
    registers = { a: 0x42, b: 0x00, c: 0x00, d: 0x00, e: 0x00, h: 0x00, l: 0x00, f: 0x00 }
    context = MicroOp::Context.new(registers, 0x0100, mmu)

    operation = MicroOperations::ReadRegister.new(:a)
    result = operation.execute(context)

    expect(result[:context].temp_variables[:a]).to eq(0x42)
    expect(result[:nb_cycles]).to eq(0)
  end

  it "reads from different registers" do
    mmu = MMU.new(Array.new(0x8000, 0x00))
    registers = { a: 0x00, b: 0x11, c: 0x22, d: 0x33, e: 0x44, h: 0x55, l: 0x66, f: 0x00 }
    context = MicroOp::Context.new(registers, 0x0100, mmu)

    operation = MicroOperations::ReadRegister.new(:h)
    result = operation.execute(context)

    expect(result[:context].temp_variables[:h]).to eq(0x55)
  end

  it "returns 0 cycles" do
    mmu = MMU.new(Array.new(0x8000, 0x00))
    registers = { a: 0x00, b: 0x00, c: 0x00, d: 0x00, e: 0x00, h: 0x00, l: 0x00, f: 0x00 }
    context = MicroOp::Context.new(registers, 0x0100, mmu)

    operation = MicroOperations::ReadRegister.new(:a)
    result = operation.execute(context)

    expect(result[:nb_cycles]).to eq(0)
  end
end
