# frozen_string_literal: true

require_relative '../lib/cartridge_loader'
require_relative '../lib/fake_keys'
require_relative '../lib/motherboard'
require_relative '../lib/utils/speed_limiter'

def build_emulator(path, with_input: false, with_limiter: false, force_cgb: false)
  cartridge = CartridgeLoader.new(path || 'roms/tetris_world_rev1.gb').cartridge
  motherboard = Motherboard.build(cartridge, force_cgb:)
  cpu = motherboard.cpu
  ppu = motherboard.ppu
  apu = motherboard.apu
  mmu = motherboard.mmu
  speed_limiter = SpeedLimiter.new if with_limiter

  return [cpu, ppu, apu, mmu, nil, cartridge, speed_limiter] unless with_input

  keys = FakeKeys.new
  mmu.joypad.key_state = keys
  [cpu, ppu, apu, mmu, keys, cartridge, speed_limiter]
end

# dma/model unused by Motherboard#run_steps, so a throwaway Motherboard is enough here
def run_steps(cpu, ppu, apu, count, speed_limiter = nil)
  Motherboard.new(cpu, ppu, apu, cpu.mmu, nil, nil).run_steps(count, speed_limiter:)
end
