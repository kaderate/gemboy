#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs a Blargg-style test ROM headlessly (no SDL/audio thread) and stops
# as soon as the test is actually finished, then dumps the final PPU
# framebuffer as a PNG for visual inspection (by a human or by reading
# the image directly).
#
# "Finished" is detected two ways:
#   - "Passed"/"Failed" text written to the serial port (SB/SC), which is
#     how most Blargg suites report their result. There is no real link
#     cable, so serial transfers are completed instantly.
#   - The CPU trapping itself in the classic end-of-test `JR $` infinite
#     loop (opcode 0x18 with offset 0xFE, i.e. jump to self) used by
#     ROMs that only render their result to the screen. This is an exact
#     byte-level check, not a "same PC seen N times" heuristic, so it
#     does not false-positive on ordinary delay loops.
#
# Usage: ruby test_roms/run_test.rb <rom.gb> [output.png]

require_relative '../lib/rom_loader'
require_relative '../lib/mmu'
require_relative '../lib/cpu'
require_relative '../lib/ppu'
require_relative '../lib/screen'

# Generous ceiling to avoid a real hang looping forever
MAX_T_CYCLES = 60 * CPU::T_CYCLES_PER_SECOND
# Remove the alpha channel from the palette, since we're not using it
PALETTE = Screen::COLOR_RGBA.map { |c| c[0..2] }.freeze

def self_loop_trap?(mmu, pc)
  mmu.read(pc) == 0x18 && mmu.read(pc + 1) == 0xFE
end

rom_path = ARGV[0]
abort 'Usage: run_test.rb <rom.gb> [output.png]' unless rom_path

out_path = ARGV[1] || "#{File.basename(rom_path, '.gb')}.png"

rom_loader = RomLoader.new(rom_path)
mmu = MMU.new(rom_loader.rom_bytes, rom_mbc_type: rom_loader.cart_type_mbc, rom_bank_count: rom_loader.bank_count,
                                    debug_config: { mmu_serial: true })
cpu = CPU.new(mmu)
ppu = PPU.new(mmu)

total_cycles = 0
loop do
  nb_cycles = cpu.step
  ppu.tick(nb_cycles)
  total_cycles += nb_cycles

  serial = mmu.serial_output || ''
  break if serial.include?('Passed') || serial.include?('Failed')
  break if self_loop_trap?(mmu, cpu.pc)
  break if total_cycles >= MAX_T_CYCLES
end

ppu.export_framebuffer_png(out_path, palette: PALETTE)

serial = mmu.serial_output || ''
puts "cycles: #{total_cycles} (#{(total_cycles / CPU::T_CYCLES_PER_SECOND).round(2)} seconds)"
puts "timed_out: #{total_cycles >= MAX_T_CYCLES}"
puts "serial: #{serial.empty? ? '(none)' : serial.inspect}"
puts "screenshot: #{out_path}"
