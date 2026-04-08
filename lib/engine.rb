require 'ruby2d'
require 'benchmark'

require_relative 'rom_loader'
require_relative 'mmu'
require_relative 'cpu'
require_relative 'ppu'
require_relative 'key_state'

class Engine
  attr_reader :logger
  attr_accessor :mmu, :cpu, :ppu, :key_state

  def initialize(rom_path, logger: Logger.new($stdout))
    @logger = logger
    setup_logger

    rom_bytes = RomLoader.new(rom_path).rom_bytes
    @mmu = MMU.new(rom_bytes)
    @cpu = CPU.new(mmu, logger:)
    @ppu = PPU.new(mmu, logger:)
    @key_state = KeyState.new

    # Queue pour synchroniser le rendu avec le thread principal
    @render_queue = Thread::Queue.new

    initialize_window
    initialize_input_handlers
    setup_main_loop
    setup_ruby2d_thread
  end

  def start
    Ruby2D::Window.show
  end

  private

  def setup_logger
    return unless logger

    logger.level = Logger::WARN
    logger.formatter = proc { |s, dt, _, msg| "[#{dt.strftime('%H:%M:%S.%L')}][#{s}] #{msg}\n" }
  end

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

  def setup_ruby2d_thread
    Ruby2D::Window.update do
      unless @render_queue.empty?
        @render_queue.pop
        ppu.render
      end
    end
  end

  def setup_main_loop
    step_count = 0

    Thread.new do
      loop do
        step_count += 1
        puts "Step #{step_count}: PC=0x#{cpu.pc.to_s(16)}" if step_count % 10000 == 0

        nb_cycles = run_cpu_step(key_state)

        # Signal to the Ruby2D thread to render the screen
        must_render = ppu.tick(nb_cycles)
        @render_queue << :render if must_render

        sleep(0.00001) if step_count % 10_000_000 == 0
        # time = Benchmark.realtime { }
        # manage_timing(time, nb_cycles)
      end
    end
  end

  def run_cpu_step(key_state)
    raise "CPU has stopped running" unless cpu.running?
    mmu.set_key_state(key_state)
    cpu.step
  end
end
