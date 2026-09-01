# frozen_string_literal: true

require_relative '../lib/cartridge_loader'
require_relative '../lib/model_selector'
require_relative '../lib/mmu'
require_relative '../lib/cpu'
require_relative '../lib/ppu'
require_relative '../lib/apu'
require_relative '../lib/dma'
require_relative '../lib/utils/speed_limiter'

class FakeKeys
  attr_accessor :up, :down, :left, :right, :a, :b, :start, :select

  def initialize = clear
  def clear = @up = @down = @left = @right = @a = @b = @start = @select = false
  def press(key) = send("#{key}=", true)
end

def build_emulator(path, with_input: false, with_limiter: false, force_cgb: false)
  cartridge = CartridgeLoader.new(path || 'roms/tetris_world_rev1.gb').cartridge
  model = ModelSelector.new(cartridge:, force_cgb:)
  mmu = MMU.from_cartridge(cartridge, debug_config: {}, model:)
  cpu = CPU.new(mmu, interrupts: mmu.interrupts, timer: mmu.timer, speed_shift: mmu.speed_shift, model:, logger: nil)

  dma = DMA.new(mmu)
  mmu.attach_dma(dma)
  ppu = PPU.new(mmu, interrupts: mmu.interrupts, dma:, logger: nil)
  mmu.attach_ppu(ppu)
  apu = APU.new(audio_queue: Thread::Queue.new, mmu:, timer: mmu.timer)
  mmu.attach_apu(apu)
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
