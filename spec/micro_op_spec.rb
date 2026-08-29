require_relative '../lib/micro_op'
require_relative '../lib/micro_operations'
require_relative '../lib/cpu'
require_relative '../lib/mmu'

RSpec.describe MicroOp do
  it 'chains multiple operations and accumulates cycles' do
    rom = build_rom
    rom[0x101] = 0x50  # Low byte of address
    rom[0x102] = 0x02  # High byte of address
    mmu = build_mmu(rom:)
    cpu = CPU.new(mmu, interrupts: mmu.interrupts)

    micro_op = MicroOp.new('CALL a16', cpu)
    micro_op.read_next_address
    micro_op.jump_to_next_address

    cycles = micro_op.execute
    expect(cycles).to eq(16) # 8 cycles from read_next_address, 8 from jump
  end

  it 'updates CPU state from context' do
    rom = build_rom
    rom[0x101] = 0x00
    rom[0x102] = 0x03
    mmu = build_mmu(rom:)
    cpu = CPU.new(mmu, interrupts: mmu.interrupts)

    micro_op = MicroOp.new('CALL a16', cpu)
    micro_op.read_next_address
    micro_op.jump_to_next_address
    micro_op.execute

    expect(cpu.pc).to eq(0x0300)
  end

  it 'reads register and stores in temp_variables' do
    mmu = build_mmu
    cpu = CPU.new(mmu, interrupts: mmu.interrupts)
    cpu.a = 0x42

    micro_op = MicroOp.new('LD r8,r8', cpu)
    micro_op.read_register(:a)
    micro_op.execute

    expect(cpu.pc).to eq(0x0100) # PC should not be modified by read_register
  end

  it 'jumps to direct address' do
    mmu = build_mmu
    cpu = CPU.new(mmu, interrupts: mmu.interrupts)

    micro_op = MicroOp.new('JP a16', cpu)
    micro_op.jump_to_address(0x0400)
    micro_op.execute

    expect(cpu.pc).to eq(0x0400)
  end

  it 'accumulates cycles from multiple operations' do
    rom = build_rom
    rom[0x101] = 0x20
    rom[0x102] = 0x04
    mmu = build_mmu(rom:)
    cpu = CPU.new(mmu, interrupts: mmu.interrupts)

    micro_op = MicroOp.new('CALL a16', cpu)
    micro_op.read_register(:a)   # 0 cycles
    micro_op.read_next_address   # 8 cycles
    micro_op.jump_to_next_address # 8 cycles

    cycles = micro_op.execute
    expect(cycles).to eq(16)
  end

  it 'preserves register state through operations' do
    mmu = build_mmu
    cpu = CPU.new(mmu, interrupts: mmu.interrupts)
    cpu.b = 0x55

    micro_op = MicroOp.new('NOP', cpu)
    micro_op.read_register(:b)
    micro_op.execute

    expect(cpu.b).to eq(0x55)
  end
end
