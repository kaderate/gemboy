# frozen_string_literal: true

require 'fileutils'
require_relative '../../test_roms/support/rom_test_runner'

# Locks the two reference results the emulator already reaches. run_all.rb grades every suite but
# always exits 0, so without this nothing fails when an accuracy win silently regresses.
RSpec.describe 'reference ROMs', :accuracy do
  ROMS_DIR = File.expand_path('../../test_roms', __dir__)
  SCREENSHOT_DIR = File.expand_path('../../tmp/accuracy', __dir__)

  # These specs run alone (tag-filtered) and the real emulator enables YJIT too: 87s -> 33s here.
  before(:all) do
    RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && !RubyVM::YJIT.enabled?
    FileUtils.mkdir_p(SCREENSHOT_DIR)
  end

  def run_rom(rom, **options)
    screenshot = File.join(SCREENSHOT_DIR, "#{File.basename(rom, '.gb')}.png")
    RomTestRunner.run(File.join(ROMS_DIR, rom), screenshot, **options)
  end

  it 'passes every cpu_instrs sub-test' do
    result = run_rom('cpu_instrs/cpu_instrs.gb')

    expect(result.status).to(eq(:passed), "serial output: #{result.serial.inspect}")
  end

  # dmg-acid2 draws one static frame then loops on vblank forever, so 3s of emulated time is
  # plenty; its verdict is the framebuffer, not the serial port.
  it 'renders dmg-acid2 pixel for pixel' do
    result = run_rom('dmg-acid2.gb',
                     max_t_cycles: 3 * CPU::T_CYCLES_PER_SECOND,
                     reference_path: File.join(ROMS_DIR, 'expected', 'dmg-acid2.png'))

    expect(result.mismatch).to(eq(0), "#{result.mismatch} pixels off the reference, see #{result.screenshot}")
  end
end
