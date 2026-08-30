# frozen_string_literal: true

require 'forwardable'
require 'logger'

require_relative 'cartridge_loader'
require_relative 'mmu'
require_relative 'cpu'
require_relative 'ppu'
require_relative 'apu'
require_relative 'screen'
require_relative 'key_state'
require_relative 'joypad'
require_relative 'interrupts'
require_relative 'timer'
require_relative 'battery_ram'
require_relative 'speed_shift'
require_relative 'mbc/rtc'
require_relative 'utils/fps_counter'
require_relative 'utils/speed_limiter'
require_relative 'utils/interval_timer'
require_relative 'debug/collector'
require_relative 'debug/probes/ppu_probe'
require_relative 'debug/probes/apu_probe'
require_relative 'debug/server'

# The main class of the emulator
class Engine
  extend Forwardable

  attr_reader :logger, :speed_limiter, :performance_timer, :cpu, :mmu, :ppu, :apu, :rtc, :speed_shift, :audio_sampler, :screen,
              :joypad, :interrupts, :timer, :audio_queue, :render_queue, :fps_queue, :debug_collector, :debug_server
  attr_accessor :cartridge, :key_state, :debug_config, :cycle_count

  def_delegators :logger, :warn, :info, :debug

  def initialize(rom_path, provided_logger: Logger.new($stdout), debug_port: nil)
    # Debug & logging
    @gb_fps_counter = FPSCounter.new
    @debug_config = { mmu_serial: false }
    setup_logger(provided_logger:, log_level: Logger::INFO)

    # Engine state
    @cycle_count = 0

    # Timers
    @speed_limiter = SpeedLimiter.new
    @performance_timer = IntervalTimer.new

    # Core components
    load_rom(rom_path)
    build_thread_queues
    build_core_components

    # External GameBoy components
    build_external_components

    # Remote debug, requires core components to be built
    build_debug_collector_and_server(debug_port)
  end

  def start
    register_battery_ram_saver
    register_signal_handlers

    start_main_loop_thread
    start_audio_thread
    start_debug_server
    start_display_loop # MUST be the last call as it blocks the main thread
  end

  private

  def build_thread_queues
    # Queues to sync audio & rendering with the main thread
    @render_queue = Thread::Queue.new
    @audio_queue  = Thread::Queue.new
    @fps_queue    = Thread::Queue.new
  end

  def build_core_components
    @joypad = Joypad.new
    @interrupts = Interrupts.new
    @timer = Timer.new
    @speed_shift = SpeedShift.new
    @mmu = MMU.from_cartridge(cartridge, debug_config:, joypad:, interrupts:, timer:, speed_shift:)
    @rtc = mmu.rtc
    @cpu = CPU.new(mmu, interrupts:, timer:, speed_shift:, logger:)
    @ppu = PPU.new(mmu, interrupts:, logger:)
    @mmu.attach_ppu(@ppu)
    @apu = APU.new(mmu:, timer:, audio_queue:)
    @mmu.attach_apu(@apu)
  end

  def build_external_components
    @audio_sampler = AudioSampler.new(audio_queue:, logger:)
    @key_state = KeyState.new
    @screen = Screen.new(render_queue:, fps_queue:, key_state:, audio_sampler:, logger:)
  end

  def load_rom(rom_path)
    cartridge_loader = CartridgeLoader.new(rom_path)
    @cartridge = cartridge_loader.cartridge
    @logger.info cartridge_loader.description
  end

  def build_debug_collector_and_server(debug_port)
    return unless debug_port

    probes = { ppu: Debug::Probes::PPUProbe.new(ppu:, mmu:), apu: Debug::Probes::APUProbe.new(apu:) }
    @debug_collector = Debug::Collector.new(probes:)
    @debug_server = Debug::Server.new(collector: @debug_collector, port: debug_port, logger:)
  end

  def setup_logger(provided_logger:, log_level:)
    @logger = provided_logger || Logger.new(File::NULL)
    logger.level = log_level
    logger.formatter = proc { |s, dt, _, msg| "[#{dt.strftime('%H:%M:%S.%L')}][#{s}] #{msg}\n" }
  end

  def start_display_loop = screen.show
  def start_audio_thread = audio_sampler.start
  def start_debug_server = debug_server&.start

  def register_battery_ram_saver
    at_exit { mmu.mbc.save_battery_ram }
  end

  def register_signal_handlers
    trap('INT') do # CTRL+C
      puts 'SIGINT'
      exit(0)
    end

    trap('QUIT') do
      puts 'SIGQUIT'
      exit(0)
    end
  end

  def start_main_loop_thread
    Thread.new do
      loop do
        @cycle_count += (t_cycles = run_cpu_step)

        dots = t_cycles >> @speed_shift.shift
        frame_pixels = ppu.tick(dots)
        apu.tick(dots)
        rtc.tick!(t_cycles)

        speed_limiter.throttle!(t_cycles)

        # A frame needs to be rendered
        next unless frame_pixels

        on_frame_completed(frame_pixels)
      end
    rescue CPU::UnknownOpcode => e
      warn "CPU ERROR: #{e.message}"
    end
  end

  def run_cpu_step
    unless cpu.running?
      warn 'CPU has stopped running'
      exit(1)
    end

    @joypad.key_state = key_state
    cpu.step
  end

  def on_frame_completed(frame_pixels)
    send_frame_pixels_to_display(frame_pixels)
    update_frame_metrics
    log_performance
  end

  def send_frame_pixels_to_display(frame_pixels)
    # Release the GVL once per frame, otherwise it can starve the display thread on CPU-intensive ROMs
    Thread.pass
    @render_queue << frame_pixels
  end

  def update_frame_metrics
    @fps_queue << @gb_fps_counter.update
    debug_collector&.frame_completed!
  end

  def log_performance
    return unless performance_timer.elapsed?

    info "Cycles: #{@cycle_count} (#{(@cycle_count / CPU::T_CYCLES_PER_SECOND.to_f).round(2)}x)"
    @cycle_count = 0
  end
end
