require 'ruby2d'
require 'benchmark'

require_relative 'rom_loader'
require_relative 'mmu'
require_relative 'cpu'
require_relative 'ppu'
require_relative 'screen'
require_relative 'key_state'

class Engine
  attr_reader :logger
  attr_accessor :mmu, :cpu, :ppu, :key_state, :screen, :cpu_timings, :ppu_timings

  def initialize(rom_path, logger: Logger.new($stdout))
    setup_logger(logger)

    rom_bytes = RomLoader.new(rom_path).rom_bytes
    @mmu = MMU.new(rom_bytes)
    @cpu = CPU.new(mmu, logger:)
    @ppu = PPU.new(mmu, logger:)
    @screen = Screen.new(logger:)
    @key_state = KeyState.new

    # Queue pour synchroniser le rendu avec le thread principal
    @render_queue = Thread::Queue.new

    # Debug
    @cpu_timings = []
    @ppu_timings = []

    initialize_window
    initialize_input_handlers
    setup_main_loop
    setup_ruby2d_thread
    setup_debugging_tools
  end

  def start
    Ruby2D::Window.show
  end

  private

  def setup_logger(logger)
    return unless logger

    @logger = logger
    logger.level = Logger::WARN
    logger.formatter = proc { |s, dt, _, msg| "[#{dt.strftime('%H:%M:%S.%L')}][#{s}] #{msg}\n" }
  end

  def initialize_window
    screen.initialize_window
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
        frambuffer = @render_queue.pop
        screen.render_framebuffer(frambuffer)
      end
    end
  end

  def setup_main_loop
    step_count = 0

    Thread.new do
      loop do
        step_count += 1
        log "Step #{step_count}: PC=0x#{cpu.pc.to_s(16)}" if step_count % 100_000 == 0

        nb_cycles = 0
        time_cpu = Benchmark.realtime do
          nb_cycles = run_cpu_step(key_state)
        end
        cpu_timings << time_cpu

        time_ppu = Benchmark.realtime do
          ppu.tick(nb_cycles).tap do |framebuffer|
            @render_queue << framebuffer if framebuffer
          end
        end
        ppu_timings << time_ppu
      end
    end
  end

  def run_cpu_step(key_state)
    raise "CPU has stopped running" unless cpu.running?

    mmu.set_key_state(key_state)
    cpu.step
  end

  def setup_debugging_tools
    puts '*' * 60
    puts "Press Enter to print debug info (average tick times and step counts)"
    puts '*' * 60

    debug_string = "\n" + '*' * 60 + "\n" + "%s\n" + '*' * 60 + "\n\n"

    Thread.new do
      loop do
        $stdin.gets # Wait for user input to print debug info

        stats = {
          CPU: {
            avg_time: (cpu_timings.sum / cpu_timings.size) * 1_000_000,
            steps: cpu_timings.size
          },
          PPU: {
            avg_time: (ppu_timings.sum / ppu_timings.size) * 1_000_000,
            steps: ppu_timings.size
          }
        }

        str = stats.map { |name, data| "  #{name} Avg Tick Time: #{format('%7.2f', data[:avg_time])}µs over #{data[:steps]} steps" }.join("\n")
        puts format(debug_string, str)
      end
    end
  end

  def log(message)
    logger&.warn(message)
  end
end
