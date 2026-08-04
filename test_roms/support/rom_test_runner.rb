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

require_relative '../../lib/rom_loader'
require_relative '../../lib/mmu'
require_relative '../../lib/cpu'
require_relative '../../lib/ppu'
require_relative '../../lib/apu'
require_relative '../../lib/screen'

module RomTestRunner
  Result = Struct.new(:status, :cycles, :timed_out, :serial, :screenshot, keyword_init: true)

  # Generous ceiling to avoid a real hang looping forever
  MAX_T_CYCLES = 60 * CPU::T_CYCLES_PER_SECOND
  # Remove the alpha channel from the palette, since we're not using it
  PALETTE = Screen::COLOR_RGBA.map { |c| c[0..2] }.freeze

  def self.run(rom_path, screenshot_path)
    rom_loader = RomLoader.new(rom_path)
    mmu = MMU.new(rom_loader.rom_bytes, rom_mbc_type: rom_loader.cart_type_mbc,
                                         rom_bank_count: rom_loader.bank_count,
                                         debug_config: { mmu_serial: true })
    cpu = CPU.new(mmu)
    ppu = PPU.new(mmu)
    apu = APU.new(mmu:, audio_queue: Queue.new)

    total_cycles = 0
    loop do
      nb_cycles = cpu.step
      ppu.tick(nb_cycles)
      apu.tick(nb_cycles)
      total_cycles += nb_cycles

      serial = mmu.serial_output || ''
      break if serial.include?('Passed') || serial.include?('Failed')
      break if self_loop_trap?(mmu, cpu.pc)
      break if total_cycles >= MAX_T_CYCLES
    end

    ppu.export_framebuffer_png(screenshot_path, palette: PALETTE)

    serial = mmu.serial_output || ''
    timed_out = total_cycles >= MAX_T_CYCLES

    Result.new(
      status: status_for(serial, timed_out),
      cycles: total_cycles,
      timed_out:,
      serial:,
      screenshot: screenshot_path
    )
  end

  def self.status_for(serial, timed_out)
    return :passed if serial.include?('Passed')
    return :failed if serial.include?('Failed')
    return :timeout if timed_out

    :visual
  end

  def self.self_loop_trap?(mmu, pc)
    mmu.read(pc) == 0x18 && mmu.read(pc + 1) == 0xFE
  end
end
