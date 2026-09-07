# frozen_string_literal: true

require_relative '../../lib/cartridge_loader'
require_relative '../../lib/save_states/state'

# The unit specs only prove the bytes survive a round trip. This one proves the emulation does:
# a state reloaded mid-run must replay the exact same frames as the run it was taken from.
RSpec.describe SaveStates::State, :accuracy do
  ROM = File.expand_path('../../test_roms/cpu_instrs/cpu_instrs.gb', __dir__)
  WARMUP = 2 * CPU::T_CYCLES_PER_SECOND
  REPLAY = CPU::T_CYCLES_PER_SECOND

  before(:all) { RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && !RubyVM::YJIT.enabled? }

  def run_for(motherboard, t_cycles)
    mmu = motherboard.mmu
    total = 0
    while total < t_cycles
      stepped = motherboard.cpu.step
      dots = stepped >> mmu.speed_shift.shift
      motherboard.ppu.tick(dots)
      motherboard.apu.tick(dots)
      mmu.rtc.tick!(stepped)
      total += stepped
    end
  end

  it 'replays the same frames from a reloaded state' do
    cartridge = CartridgeLoader.new(ROM).cartridge
    motherboard = Motherboard.build(cartridge, debug_config: { mmu_serial: true })

    run_for(motherboard, WARMUP)
    state = described_class.dump(motherboard, cartridge)
    frame_at_save = motherboard.ppu.framebuffer.pixels_frame.dup

    run_for(motherboard, REPLAY)
    reference_frame = motherboard.ppu.framebuffer.pixels_frame.dup
    reference_serial = motherboard.mmu.serial_output.dup

    reloaded = described_class.load(state, cartridge)
    run_for(reloaded, REPLAY)

    expect(reference_frame).not_to eq(frame_at_save) # guards against comparing two idle frames
    expect(reloaded.mmu.serial_output).to eq(reference_serial)
    expect(reloaded.ppu.framebuffer.pixels_frame).to eq(reference_frame)
  end
end
