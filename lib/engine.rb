require 'ruby2d'
require 'benchmark'

require_relative 'rom_loader'
require_relative 'mmu'
require_relative 'cpu'
require_relative 'ppu'
require_relative 'key_state'

class Engine
  FRAME_RATE = 59.7 # Real one is 59.7

  attr_accessor :mmu, :cpu, :ppu, :key_state

  def initialize(rom_path, logger: Logger.new($stdout))
    logger&.level = Logger::DEBUG

    rom_bytes = RomLoader.new(rom_path).rom_bytes
    @mmu = MMU.new(rom_bytes)
    @cpu = CPU.new(mmu, logger:)
    @ppu = PPU.new(mmu, logger:)
    @key_state = KeyState.new

    initialize_window
    initialize_input_handlers
    setup_main_loop
  end

  def start
    Ruby2D::Window.show
  end

  private

  def initialize_window
    ppu.initialize_window
  end

  def initialize_input_handlers
    Ruby2D::Window.on :key_down do |event|
      key_state.update(event.key, true)
    end

    Ruby2D::Window.on :key_up do |event|
      key_state.update(event.key, false)
    end
  end

  def setup_main_loop
    Ruby2D::Window.update do
      time = Benchmark.realtime do
        nb_cycles = run_cpu_step(key_state)
        ppu.tick(nb_cycles)
      end

      # manage_timing(time, nb_cycles)
    end
  end

  def run_cpu_step(key_state)
    raise "CPU has stopped running" unless cpu.running?
    mmu.set_key_state(key_state)
    cpu.step
  end

  def manage_timing(time, nb_cycles)
    puts "  Tick time: #{(time * 1000).round(2)} ms | Cycles: #{nb_cycles}"
    puts ''
    frame_time = nb_cycles.to_f / 1_790_000 # Convert cycles to seconds based on CPU clock speed
    sleep_time = (1.0 / FRAME_RATE) - frame_time

    sleep(sleep_time) if sleep_time > 0
  end
end
