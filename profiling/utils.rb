# frozen_string_literal: true

require_relative '../lib/cartridge_loader'
require_relative '../lib/motherboard'
require_relative '../lib/utils/speed_limiter'

class FakeKeys
  attr_accessor :up, :down, :left, :right, :a, :b, :start, :select

  def initialize = clear
  def clear = @up = @down = @left = @right = @a = @b = @start = @select = false
  def press(key) = send("#{key}=", true)
end

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

def run_steps(cpu, ppu, apu, count, speed_limiter = nil)
  total_cycles = 0
  mmu = cpu.mmu
  rtc = mmu.rtc
  speed_shift = mmu.speed_shift
  count.times do
    t_cycles = cpu.step
    dots = t_cycles >> speed_shift.shift
    ppu.tick(dots)
    apu.tick(dots)
    rtc.tick!(t_cycles)
    total_cycles += t_cycles
    speed_limiter&.throttle!(dots)
  end
  total_cycles
end
