require 'gosu'
require 'benchmark'
require 'memory_profiler'

require_relative 'rom_loader'
require_relative 'mmu'
require_relative 'cpu'
require_relative 'ppu'
require_relative 'screen'
require_relative 'key_state'
require_relative 'utils/fps_counter'

class Engine
  DEBUG_STRING = "\n" + '*' * 60 + "\n" + "%s\n" + '*' * 60 + "\n\n"

  attr_reader :logger
  attr_accessor :mmu, :cpu, :ppu, :key_state, :screen, :debug_config

  def initialize(rom_path, logger: Logger.new($stdout))
    setup_logger(logger)

    # Debug
    @gb_fps_counter = FPSCounter.new
    @debug_config = { gc: false, memory: false, mmu_serial: false }

    # Queue pour synchroniser le rendu avec le thread principal
    @render_queue = Thread::Queue.new
    @internal_fps_queue = Thread::Queue.new

    # Game components
    rom_bytes = RomLoader.new(rom_path).rom_bytes
    @mmu = MMU.new(rom_bytes, debug_config:)
    @cpu = CPU.new(mmu, logger:)
    @ppu = PPU.new(mmu, logger:)
    @key_state = KeyState.new
    @screen = Screen.new(render_queue: @render_queue, fps_queue: @internal_fps_queue, key_state:, logger:)

    setup_debugging_tools
  end

  def start
    setup_main_loop
    start_display_thread
  end

  private

  def setup_logger(logger)
    return unless logger

    @logger = logger
    logger.level = Logger::WARN
    logger.formatter = proc { |s, dt, _, msg| "[#{dt.strftime('%H:%M:%S.%L')}][#{s}] #{msg}\n" }
  end

  def start_display_thread
    screen.show
  end

  def setup_main_loop
    t_cycle_count = 0

    Thread.new do
      loop do
        t_cycle_count += 1
        log "T-cycle #{t_cycle_count}: PC=0x#{cpu.pc.to_s(16)}" if t_cycle_count % 1_000_000 == 0

        nb_cycles = run_cpu_step
        frame_pixels = ppu.tick(nb_cycles)

        if frame_pixels
          @render_queue << frame_pixels
          @gb_fps_counter.update # { |count, _| log "GameBoy Display FPS: #{count}" }
          @internal_fps_queue << @gb_fps_counter.last_fps

          sleep 0.002
        end
      end
    end
  end

  def run_cpu_step
    raise "CPU has stopped running" unless cpu.running?

    mmu.set_key_state(key_state)
    cpu.step
  end

  def setup_debugging_tools
    if debug_config[:gc]
      Thread.new do
        loop do
          sleep 3
          stat = GC.stat
          str = "GC runs: #{stat[:count]} | Heap alloc: #{stat[:heap_allocated_pages]} pages | Minor: #{stat[:minor_gc_count]} Major: #{stat[:major_gc_count]}"
          log DEBUG_STRING % str
        end
      end
    end

    if debug_config[:memory]
      Thread.new do
        loop do
          sleep 10
          log "******** Profiling memory... ********"
          report = MemoryProfiler.report { 5_000.times { nb_cycles = run_cpu_step(key_state); ppu.tick(nb_cycles) } }
          report.pretty_print(to_file: '/tmp/alloc_report.txt')
          log DEBUG_STRING % "Report written to /tmp/alloc_report.txt"
        end
      end
    end
  end

  def log(message)
    logger&.warn(message)
  end
end
