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

require 'zlib'
require_relative '../lib/rom_loader'
require_relative '../lib/mmu'
require_relative '../lib/cpu'
require_relative '../lib/ppu'

ADDR_SB = 0xFF01
ADDR_SC = 0xFF02
MAX_T_CYCLES = 60 * CPU::T_CYCLES_PER_SECOND # generous ceiling to avoid a real hang looping forever

# Same palette as lib/screen.rb::COLOR_RGBA
PALETTE = [
  [0x9A, 0x9E, 0x3F],
  [0x49, 0x6B, 0x22],
  [0x0E, 0x45, 0x0B],
  [0x1B, 0x2A, 0x09]
].freeze

class MMU
  alias orig_write write
  attr_accessor :serial_output

  # Intercept serial transfer requests and complete them instantly, since
  # this emulator has no real link-cable peer.
  def write(addr, value, force: false)
    if addr == ADDR_SC && (value & 0x80 != 0)
      (self.serial_output ||= +'') << read(ADDR_SB).chr
      orig_write(ADDR_SC, value & 0x7F, force:)
      set_interrupt_requested(:serial) if interrupts_enabled_mask[:serial]
    else
      orig_write(addr, value, force:)
    end
  end
end

def self_loop_trap?(mmu, pc)
  mmu.read(pc) == 0x18 && mmu.read(pc + 1) == 0xFE
end

def write_png(path, pixels, width, height, palette)
  raw = +''.b
  height.times do |y|
    raw << "\x00".b # filter type: None
    width.times { |x| raw << palette[pixels[(y * width) + x]].pack('C3') }
  end

  idat = Zlib::Deflate.deflate(raw)
  chunk = lambda do |type, data|
    [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
  end

  File.open(path, 'wb') do |f|
    f.write("\x89PNG\r\n\x1A\n".b)
    f.write(chunk.call('IHDR', [width, height, 8, 2, 0, 0, 0].pack('N2C5')))
    f.write(chunk.call('IDAT', idat))
    f.write(chunk.call('IEND', ''.b))
  end
end

rom_path = ARGV[0]
abort 'Usage: run_test.rb <rom.gb> [output.png]' unless rom_path

out_path = ARGV[1] || "#{File.basename(rom_path, '.gb')}.png"

rom_loader = RomLoader.new(rom_path)
mmu = MMU.new(rom_loader.rom_bytes, rom_mbc_type: rom_loader.cart_type_mbc, rom_bank_count: rom_loader.bank_count)
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

write_png(out_path, ppu.framebuffer.pixels_frame, PPU::WINDOW_WIDTH, PPU::WINDOW_HEIGHT, PALETTE)

serial = mmu.serial_output || ''
puts "cycles: #{total_cycles} (#{(total_cycles / CPU::T_CYCLES_PER_SECOND).round(2)} seconds)"
puts "timed_out: #{total_cycles >= MAX_T_CYCLES}"
puts "serial: #{serial.empty? ? '(none)' : serial.inspect}"
puts "screenshot: #{out_path}"
