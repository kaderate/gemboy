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
require_relative 'utils/fps_counter'

# The main class of the emulator
class Engine
  DEBUG_STRING = format("\n%<sep>s\n%%s\n%<sep>s\n", sep: '*' * 60)
  TARGET_FRAME_DURATION_SEC = (1 / 59.7)

  attr_reader :logger
  attr_accessor :mmu, :cpu, :ppu, :apu, :audio_sampler, :key_state, :screen, :debug_config

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
    rom_bytes = RomLoader.new(rom_path).rom_bytes
    @mmu = MMU.new(rom_bytes, debug_config:)
    @cpu = CPU.new(mmu, logger:)
    @ppu = PPU.new(mmu, logger:)
    @apu = APU.new(audio_queue: @audio_queue, mmu: @mmu)
    @audio_sampler = AudioSampler.new(audio_queue: @audio_queue, logger:)
    @key_state = KeyState.new
    @screen = Screen.new(render_queue: @render_queue, fps_queue: @internal_fps_queue, key_state:, logger:)

    setup_debugging_tools
  end

  def start
    setup_main_loop
    start_audio_thread
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

  def start_audio_thread
    audio_sampler.start
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

        @render_queue << frame_pixels
        @gb_fps_counter.update # { |count, _| log "GameBoy Display FPS: #{count}" }
        @internal_fps_queue << @gb_fps_counter.last_fps

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Log emulation speed
        if now - last_log_time >= 1.0
          puts "T-cycles/sec: #{t_cycle_count} (target: 4_194_304, ratio: #{(t_cycle_count / 4_194_304.0).round(2)}x)"
          t_cycle_count = 0
          last_log_time = now
        end

        # Frame limiter
        frame_duration = now - last_frame_time
        # puts "Frame duration: #{(frame_duration * 1000).round(2)}/#{(TARGET_FRAME_DURATION_SEC * 1000).round(2)}ms"
        last_frame_time = now
        sleep(TARGET_FRAME_DURATION_SEC - frame_duration) if frame_duration < TARGET_FRAME_DURATION_SEC # 0.0001
      end
    rescue CPU::UnknownOpcode => e
      log "CPU ERROR: #{e.message} at PC 0x#{cpu.pc.to_s(16).upcase}"
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
          str = "GC runs: #{stat[:count]} | Heap alloc: #{stat[:heap_allocated_pages]} pages | Minor: #{stat[:minor_gc_count]} Major: #{stat[:major_gc_count]}"
          log DEBUG_STRING % str
        end
      end
    end

    return unless debug_config[:memory]

    Thread.new do
      loop do
        sleep 10
        log '******** Profiling memory... ********'
        report = MemoryProfiler.report do
          5_000.times do
            nb_cycles = run_cpu_step(key_state)
            ppu.tick(nb_cycles)
          end
        end
        report.pretty_print(to_file: '/tmp/alloc_report.txt')
        log DEBUG_STRING % 'Report written to /tmp/alloc_report.txt'
      end
    end
  end

  def log(message)
    logger&.warn(message)
  end
end
