require_relative '../../lib/micro_operations'
require_relative '../../lib/cpu'
require_relative '../../lib/mmu'

RSpec.describe MicroOperations::ReadNextAddress do
  it "reads 16-bit value from memory at PC+1" do
    rom = Array.new(0x8000, 0x00)
    rom[0x101] = 0x50  # Low byte
    rom[0x102] = 0x01  # High byte
    mmu = MMU.new(rom)
    registers = { a: 0x00, b: 0x00, c: 0x00, d: 0x00, e: 0x00, h: 0x00, l: 0x00, f: 0x00 }
    context = MicroOp::Context.new(registers, 0x0100, mmu)

    operation = MicroOperations::ReadNextAddress.new
    result = operation.execute(context)

    expect(result[:context].temp_variables[:next_address]).to eq(0x0150)
  end

  it "returns 8 cycles" do
    rom = Array.new(0x8000, 0x00)
    mmu = MMU.new(rom)
    registers = { a: 0x00, b: 0x00, c: 0x00, d: 0x00, e: 0x00, h: 0x00, l: 0x00, f: 0x00 }
    context = MicroOp::Context.new(registers, 0x0100, mmu)

    operation = MicroOperations::ReadNextAddress.new
    result = operation.execute(context)

    expect(result[:nb_cycles]).to eq(8)
  end

  it "does not modify PC" do
    rom = Array.new(0x8000, 0x00)
    mmu = MMU.new(rom)
    registers = { a: 0x00, b: 0x00, c: 0x00, d: 0x00, e: 0x00, h: 0x00, l: 0x00, f: 0x00 }
    context = MicroOp::Context.new(registers, 0x0100, mmu)

    operation = MicroOperations::ReadNextAddress.new
    result = operation.execute(context)

    expect(result[:context].pc).to eq(0x0100)
  end
end
