# frozen_string_literal: true

require_relative '../lib/rom_loader'
require_relative '../lib/mmu'
require_relative '../lib/cpu'
require_relative '../lib/ppu'
require_relative '../lib/apu'

class FakeKeys
  attr_accessor :up, :down, :left, :right, :a, :b, :start, :select

  def initialize = clear
  def clear = @up = @down = @left = @right = @a = @b = @start = @select = false
  def press(key) = send("#{key}=", true)
end

def build_emulator(path, with_input: false)
  cartridge = RomLoader.new(path || 'roms/tetris_world_rev1.gb').cartridge
  mmu = MMU.from_cartridge(cartridge, debug_config: {})
  cpu = CPU.new(mmu, logger: nil)
  ppu = PPU.new(mmu, logger: nil)
  apu = APU.new(audio_queue: Thread::Queue.new, mmu: mmu)

  return [cpu, ppu, apu, mmu, nil, cartridge] unless with_input

  keys = FakeKeys.new
  mmu.set_key_state(keys)
  [cpu, ppu, apu, mmu, keys, cartridge]
end

def run_steps(cpu, ppu, apu, count)
  total_cycles = 0
  count.times do
    nb_cycles = cpu.step
    ppu.tick(nb_cycles)
    apu.tick(nb_cycles)
    total_cycles += nb_cycles
  end
  total_cycles
end
