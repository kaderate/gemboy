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

# The main class of the emulator
class Engine
  DEBUG_STRING = format("\n%<sep>s\n%%s\n%<sep>s\n", sep: '*' * 60)
  TARGET_FRAME_DURATION_SEC = (1 / 59.7)

  attr_reader :logger
  attr_accessor :cartridge, :mmu, :cpu, :ppu, :apu, :audio_sampler, :key_state, :screen, :debug_config

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

    @mmu = MMU.from_cartridge(cartridge, debug_config:)
    @cpu = CPU.new(mmu, logger:)
    @ppu = PPU.new(mmu, logger:)
    @apu = APU.new(audio_queue: @audio_queue, mmu:)
    @audio_sampler = AudioSampler.new(audio_queue: @audio_queue, logger:)
    @key_state = KeyState.new
    @screen = Screen.new(render_queue: @render_queue, fps_queue: @internal_fps_queue, key_state:, logger:)

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
    t_cycle_count = 0
    last_log_time = last_frame_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    Thread.new do
      loop do
        nb_cycles = run_cpu_step
        frame_pixels = ppu.tick(nb_cycles)
        apu.tick(nb_cycles)
        t_cycle_count += nb_cycles

        next unless frame_pixels

        # Cession volontaire du GVL une fois par frame GB complétée (~60x/sec à vitesse
        # réelle) : sans ça, ce thread ne cède jamais la main explicitement et peut affamer
        # le thread d'affichage sur les ROMs avec beaucoup de travail Ruby par instruction.
        Thread.pass

        @render_queue << frame_pixels
        @gb_fps_counter.update # { |count, _| warn "GameBoy Display FPS: #{count}" }
        @internal_fps_queue << @gb_fps_counter.last_fps

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Log emulation speed
        if now - last_log_time >= 1.0
          logger.info "T-cycles/sec: #{t_cycle_count} (#{(t_cycle_count / 4_194_304.0).round(2)}x)"
          t_cycle_count = 0
          last_log_time = now
        end

        # Frame limiter
        frame_duration = now - last_frame_time
        # logger&.debug { "Frame duration: #{(frame_duration * 1000).round(2)}/#{(TARGET_FRAME_DURATION_SEC * 1000).round(2)}ms" }
        last_frame_time = now
        sleep(TARGET_FRAME_DURATION_SEC - frame_duration) if frame_duration < TARGET_FRAME_DURATION_SEC # 0.0001
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
