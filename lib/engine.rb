require 'ruby2d'
require 'benchmark'

require_relative 'rom_loader'
require_relative 'cpu'
require_relative 'ppu'

class Engine
  FRAME_RATE = 5

  attr_accessor :cpu, :ppu

  def initialize(rom_path)
    rom_bytes = RomLoader.new(rom_path).rom_bytes
    @cpu = CPU.new(rom_bytes)
    @ppu = PPU.new(cpu)

    initialize_window
    setup_main_loop
  end

  def start
    Ruby2D::Window.show
  end

  private

  def initialize_window
    ppu.initialize_window
  end

  def setup_main_loop
    Ruby2D::Window.update do
      time = Benchmark.realtime do
        run_cpu_step
        run_ppu_step
      end

      manage_timing(time)
    end
  end

  def run_cpu_step
    raise "CPU has stopped running" unless cpu.running?
    cpu.step
  end

  def run_ppu_step
    ppu.render
  end

  def manage_timing(time)
    puts "  Frame time: #{(time * 1000).round(2)} ms"
    puts ''
    sleep_time = (1.0 / FRAME_RATE) - time
    sleep(sleep_time) if sleep_time > 0
  end
end
