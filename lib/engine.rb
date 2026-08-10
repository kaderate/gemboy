# frozen_string_literal: true

require 'benchmark'
# require 'memory_profiler'

require_relative 'rom_loader'
require_relative 'mmu'
require_relative 'cpu'
require_relative 'ppu'
require_relative 'apu'
require_relative 'screen'
require_relative 'key_state'
require_relative 'battery_ram'
require_relative 'utils/fps_counter'
require_relative 'utils/frame_limiter'
require_relative 'utils/interval_timer'

# The main class of the emulator
class Engine
  DEBUG_STRING = format("\n%<sep>s\n%%s\n%<sep>s\n", sep: '*' * 60)

  attr_reader :logger, :frame_limiter, :performance_timer, :cpu, :mmu, :ppu, :apu, :audio_sampler, :screen
  attr_accessor :cartridge, :key_state, :debug_config

  # If a logger is needed: Logger.new($stdout))
  def initialize(rom_path, logger: Logger.new($stdout))
    setup_logger(logger)

    # Debug
    @gb_fps_counter = FPSCounter.new
    @debug_config = { gc: false, memory: false, mmu_serial: false }

    # Queue pour synchroniser le rendu avec le thread principal
    @render_queue = Thread::Queue.new
    @audio_queue = Thread::Queue.new
    @internal_fps_queue = Thread::Queue.new

    # Game components
    rom_loader = RomLoader.new(rom_path)
    @cartridge = rom_loader.cartridge
    @cartridge_description = rom_loader.description

    @frame_limiter = FrameLimiter.new
    @performance_timer = IntervalTimer.new(target_in_seconds: 1)
    @mmu = MMU.from_cartridge(cartridge, debug_config:)
    @cpu = CPU.new(mmu, logger:)
    @ppu = PPU.new(mmu, logger:)
    @apu = APU.new(audio_queue: @audio_queue, mmu:)
    @audio_sampler = AudioSampler.new(audio_queue: @audio_queue, logger:)
    @key_state = KeyState.new
    @screen = Screen.new(render_queue: @render_queue, fps_queue: @internal_fps_queue, key_state:,
                         audio_sampler: @audio_sampler, logger:)

    setup_debugging_tools
  end

  def start
    display_cartridge_info
    setup_main_loop
    start_audio_thread
    start_display_thread
    register_battery_ram_saver
  end

  private

  def display_cartridge_info
    @logger.info @cartridge_description
  end

  def setup_logger(logger)
    return unless logger

    @logger = logger
    logger.level = Logger::INFO
    logger.formatter = proc { |s, dt, _, msg| "[#{dt.strftime('%H:%M:%S.%L')}][#{s}] #{msg}\n" }
  end

  def start_display_thread
    screen.show
  end

  def start_audio_thread
    audio_sampler.start
  end

  def register_battery_ram_saver
    # In case of an interruption, save the battery RAM
    at_exit { BatteryRAM.save(cartridge.battery_ram_path, @mmu.external_ram) if cartridge.with_battery? }
  end

  def setup_main_loop
    cycle_count = 0

    Thread.new do
      loop do
        nb_cycles = run_cpu_step
        frame_pixels = ppu.tick(nb_cycles)
        apu.tick(nb_cycles)
        cycle_count += nb_cycles

        next unless frame_pixels

        # Lâche le GVL une fois par frame. Peut sinon affamer le thread display sur roms CPU-intensive.
        Thread.pass

        @render_queue << frame_pixels
        @gb_fps_counter.update # { |count, _| warn "GameBoy Display FPS: #{count}" }
        @internal_fps_queue << @gb_fps_counter.last_fps

        # Performance timer & frame limiter
        cycle_count = 0 if performance_timer.elapsed?
        frame_limiter.limit_frames_per_second!
      end
    rescue CPU::UnknownOpcode => e
      warn "CPU ERROR: #{e.message}"
    end
  end

  def run_cpu_step
    raise 'CPU has stopped running' unless cpu.running?

    mmu.set_key_state(key_state)
    cpu.step
  end

  def setup_debugging_tools
    if debug_config[:gc]
      Thread.new do
        loop do
          sleep 3
          stat = GC.stat
          str = "GC runs: #{stat[:count]} | Heap alloc: #{stat[:heap_allocated_pages]} pages | " \
                "Minor: #{stat[:minor_gc_count]} Major: #{stat[:major_gc_count]}"
          warn DEBUG_STRING % str
        end
      end
    end

    return unless debug_config[:memory]

    Thread.new do
      loop do
        sleep 10
        warn '******** Profiling memory... ********'
        report = MemoryProfiler.report do
          5_000.times do
            nb_cycles = run_cpu_step(key_state)
            ppu.tick(nb_cycles)
          end
        end
        report.pretty_print(to_file: '/tmp/alloc_report.txt')
        warn DEBUG_STRING % 'Report written to /tmp/alloc_report.txt'
      end
    end
  end

  def warn(message)
    logger&.warn(message)
  end
end
