# frozen_string_literal: true

# Runs a ROM headlessly and stops at the FIRST moment the CPU fetches an opcode from blank/uninitialized memory
# (0xFF followed by 0xFF), keeping the last N executed instructions (PC, opcode, SP) so we can see the trace.

require_relative 'utils'

path = ARGV[0] || File.join(__dir__, '../test_roms/mem_timing/mem_timing-2.gb')
TRACE_SIZE = 40
MAX_T_CYCLES = 50_000_000

cpu, ppu, apu, mmu = build_emulator(path)
speed_shift = mmu.speed_shift

trace = []
total = 0

loop do
  pc = cpu.pc
  opcode = mmu.read(pc)
  trace << [pc, opcode, cpu.sp]
  trace.shift if trace.size > TRACE_SIZE

  t_cycles = cpu.step
  dots = t_cycles >> speed_shift.shift
  ppu.tick(dots)
  apu.tick(dots)
  total += t_cycles

  if opcode == 0xFF && mmu.read(pc + 1) == 0xFF
    gb_time = format('%.2f', total / CPU::T_CYCLES_PER_SECOND.to_f)
    puts "Atterri en mémoire vide à PC=0x#{pc.to_s(16).upcase} après #{total} cycles (#{gb_time}s GB time)"
    puts "#{trace.size} dernieres instructions (PC, opcode, SP) :"
    trace.each { |p, o, sp| printf("  PC=0x%<pc>04X opcode=0x%<op>02X SP=0x%<sp>04X\n", pc: p, op: o, sp: sp) }
    exit
  end

  if total > MAX_T_CYCLES
    puts "Aucune chute dans le vide détéctée apres #{total} cycles."
    exit
  end
end
