#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs a ROM headlessly and stops at the FIRST moment the CPU fetches an opcode from blank/uninitialized memory
# (0xFF followed by 0xFF), keeping the last N executed instructions (PC, opcode, SP) so we can see the trace.

repo_idx = ARGV.index('--repo')
repo_path = repo_idx ? ARGV.slice!(repo_idx, 2)[1] : Dir.pwd
LIB = File.expand_path('lib', repo_path)
$LOAD_PATH.unshift(LIB)

require 'rom_loader'
require 'mmu'
require 'cpu'
require 'ppu'

path = ARGV[0] || File.join(repo_path, 'roms/tests/mem_timing/mem_timing-2.gb')
TRACE_SIZE = 40
MAX_T_CYCLES = 50_000_000
CYCLES_PER_SEC = 4_194_304.0

rom_bytes = RomLoader.new(path).rom_bytes
mmu = MMU.new(rom_bytes)
cpu = CPU.new(mmu)
ppu = PPU.new(mmu)

trace = []
total = 0

loop do
  pc = cpu.pc
  opcode = mmu.read(pc)
  trace << [pc, opcode, cpu.sp]
  trace.shift if trace.size > TRACE_SIZE

  nb = cpu.step
  ppu.tick(nb)
  total += nb

  if opcode == 0xFF && mmu.read(pc + 1) == 0xFF
    gb_time = format('%.2f', total / CYCLES_PER_SEC)
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
