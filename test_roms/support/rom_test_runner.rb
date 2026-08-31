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
#     ROMs that only render their result to the screen.
#   - The PC staying on the exact same address for many consecutive steps
#     (STUCK_PC_THRESHOLD), which catches other kinds of hangs (e.g. a
#     HALT waiting on an interrupt that never comes) that aren't the
#     exact `JR $` pattern above. Treated the same as a timeout.
#
# The verdict comes from the serial port, unless a `reference_path` is given: the final
# framebuffer is then compared pixel per pixel to that reference image, which is the only way to
# grade a ROM whose result is a picture (dmg-acid2) rather than a "Passed"/"Failed" string.

require_relative '../../lib/cartridge_loader'
require_relative '../../lib/model_selector'
require_relative '../../lib/mmu'
require_relative '../../lib/cpu'
require_relative '../../lib/ppu'
require_relative '../../lib/apu'
require_relative 'png_reader'

module RomTestRunner
  Result = Struct.new(:status, :cycles, :timed_out, :serial, :screenshot, :mismatch, keyword_init: true)

  # Generous ceiling to avoid a real hang looping forever
  MAX_T_CYCLES = 60 * CPU::T_CYCLES_PER_SECOND
  # Number of consecutive steps with an unchanged PC before we consider it stuck
  STUCK_PC_THRESHOLD = 500_000

  def self.run(rom_path, screenshot_path, max_t_cycles: MAX_T_CYCLES, reference_path: nil) # rubocop:disable Metrics/MethodLength
    cartridge = CartridgeLoader.new(rom_path).cartridge
    model = ModelSelector.new(cartridge:)
    mmu = MMU.from_cartridge(cartridge, debug_config: { mmu_serial: true }, model:)
    cpu = CPU.new(mmu, interrupts: mmu.interrupts, timer: mmu.timer, model:)
    ppu = PPU.new(mmu, interrupts: mmu.interrupts)
    mmu.attach_ppu(ppu)
    apu = APU.new(mmu:, timer: mmu.timer, audio_queue: Queue.new)
    mmu.attach_apu(apu)

    total_cycles = 0
    last_pc = nil
    stuck_count = 0
    stuck = false
    loop do
      nb_cycles = cpu.step
      ppu.tick(nb_cycles)
      apu.tick(nb_cycles)
      mmu.rtc.tick!(nb_cycles)
      total_cycles += nb_cycles

      stuck_count = cpu.pc == last_pc ? stuck_count + 1 : 0
      last_pc = cpu.pc
      stuck = stuck_count >= STUCK_PC_THRESHOLD

      serial = mmu.serial_output || ''
      break if serial.include?('Passed') || serial.include?('Failed')
      break if self_loop_trap?(mmu, cpu.pc)
      break if stuck
      break if total_cycles >= max_t_cycles
    end

    ppu.export_framebuffer_png(screenshot_path)

    serial = mmu.serial_output || ''
    timed_out = stuck || total_cycles >= max_t_cycles
    mismatch = reference_path && count_mismatches(ppu.framebuffer.pixels_frame, reference_path)

    Result.new(
      status: status_for(serial, timed_out, mismatch),
      cycles: total_cycles,
      timed_out:,
      serial:,
      screenshot: screenshot_path,
      mismatch:
    )
  end

  def self.status_for(serial, timed_out, mismatch = nil)
    return :passed if serial.include?('Passed')
    return :failed if serial.include?('Failed')
    return mismatch.zero? ? :passed : :failed unless mismatch.nil?
    return :timeout if timed_out

    :visual
  end

  # References are stored as plain grayscale PNGs (0 = black), the framebuffer holds DMG palette
  # colors (index 0 = lightest), hence the inversion when resolving the reference to RGB.
  def self.count_mismatches(pixels, reference_path)
    reference = PngReader.read(reference_path)
    if reference.pixels.size != pixels.size
      raise ArgumentError, "#{reference_path}: expected #{pixels.size} pixels, got #{reference.pixels.size}"
    end

    reference_colors = reference.pixels.map { |shade| PPU::DotDrawer::COLOR_RGBA_SDL.fetch(3 - shade) }
    pixels.each_with_index.count { |color, i| color != reference_colors[i] }
  end

  def self.self_loop_trap?(mmu, pc)
    mmu.read(pc) == 0x18 && mmu.read(pc + 1) == 0xFE
  end
end
