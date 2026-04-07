require_relative '../lib/cpu'
require_relative '../lib/mmu'
require_relative '../lib/micro_op'

RSpec.describe "Micro-ops integration with CPU" do
  it "uses micro_op for JP a16 (0xC3) when enabled" do
    rom = Array.new(0x8000, 0x00)
    rom[0x100] = 0xC3  # JP a16 opcode
    rom[0x101] = 0x50  # Low byte of target address
    rom[0x102] = 0x02  # High byte of target address
    mmu = MMU.new(rom)
    cpu = CPU.new(mmu)

    # Build micro-op for JP a16
    cpu.opcodes_with_micro_ops[0xC3] = MicroOp.new("JP a16", cpu).read_next_address.jump_to_next_address

    # Enable micro_ops
    cpu.config.use_micro_ops = true

    # Execute the step
    cycles = cpu.step

    # Verify the jump was executed
    expect(cpu.pc).to eq(0x0250)
    expect(cycles).to eq(8)  # 8 cycles from read_next_address
  end

  it "falls back to legacy implementation when micro_ops disabled" do
    rom = Array.new(0x8000, 0x00)
    rom[0x100] = 0xC3  # JP a16 opcode
    rom[0x101] = 0x00
    rom[0x102] = 0x03
    mmu = MMU.new(rom)
    cpu = CPU.new(mmu)

    # Don't register or enable micro_ops
    cpu.config.use_micro_ops = false

    # Execute the step
    cycles = cpu.step

    # Verify legacy implementation was used
    expect(cpu.pc).to eq(0x0300)
    expect(cycles).to eq(16)  # 16 cycles for legacy JP a16
  end

  it "falls back to legacy implementation when use_micro_ops disabled" do
    rom = Array.new(0x8000, 0x00)
    rom[0x100] = 0xC3  # JP a16 opcode
    rom[0x101] = 0x00
    rom[0x102] = 0x04
    mmu = MMU.new(rom)
    cpu = CPU.new(mmu)

    # Disable micro_ops (default)
    cpu.config.use_micro_ops = false

    # Execute the step
    cycles = cpu.step

    # Verify legacy implementation was used
    expect(cpu.pc).to eq(0x0400)
    expect(cycles).to eq(16)
  end

  it "uses micro_ops for multiple different opcodes" do
    rom = Array.new(0x8000, 0x00)
    # First instruction: JP a16
    rom[0x100] = 0xC3
    rom[0x101] = 0x10
    rom[0x102] = 0x01  # Jump to 0x0110
    # Second instruction at 0x0110: NOP (legacy)
    rom[0x110] = 0x00

    mmu = MMU.new(rom)
    cpu = CPU.new(mmu)

    # Build micro-op for JP a16
    cpu.opcodes_with_micro_ops[0xC3] = MicroOp.new("JP a16", cpu).read_next_address.jump_to_next_address

    # Enable micro_ops
    cpu.config.use_micro_ops = true

    # Execute first instruction (JP a16 via micro_op)
    cycles1 = cpu.step
    expect(cpu.pc).to eq(0x0110)
    expect(cycles1).to eq(8)

    # Execute second instruction (NOP via legacy)
    cycles2 = cpu.step
    expect(cpu.pc).to eq(0x0111)
    expect(cycles2).to eq(4)
  end
end
