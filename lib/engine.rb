# frozen_string_literal: true

require 'forwardable'
require 'logger'
require 'rbconfig'

require_relative 'rom_loader'
require_relative 'mmu'
require_relative 'cpu'
require_relative 'ppu'
require_relative 'apu'
require_relative 'screen'
require_relative 'key_state'
require_relative 'battery_ram'
require_relative 'utils/fps_counter'
require_relative 'utils/speed_limiter'
require_relative 'utils/interval_timer'

# The main class of the emulator
class Engine
  extend Forwardable

  attr_reader :logger, :speed_limiter, :performance_timer, :cpu, :mmu, :ppu, :apu, :audio_sampler, :screen,
              :audio_queue, :render_queue, :fps_queue
  attr_accessor :cartridge, :key_state, :debug_config, :cycle_count

  def_delegators :logger, :warn, :info, :debug

  def self.build_with_rom
    usage_and_exit if ARGV.size > 1

    rom_path = ARGV.empty? ? rom_path_from_dialog : ARGV[0].strip
    new(rom_path)
  end

  def self.rom_path_from_dialog
    usage_and_exit unless RbConfig::CONFIG['host_os'].match?(/darwin/)

    prompt = 'POSIX path of (choose file with prompt "ROM" of type {"gb","gbc"})'
    rom_path = `osascript -e '#{prompt}' 2>/dev/null`.strip
    exit(0) if rom_path.empty? # dialog cancelled

    puts "Selected ROM: #{rom_path}" # logger not yet initialized
    rom_path
  end

  def self.usage_and_exit
    puts "Usage: #{$PROGRAM_NAME} <rom_path>"
    puts '  rom_path: path to a DMG/GBC ROM (optional on macOS, where a file picker opens)'
    exit(1)
  end

  def initialize(rom_path, provided_logger: Logger.new($stdout))
    # Debug & logging
    @gb_fps_counter = FPSCounter.new
    @debug_config = { mmu_serial: false }
    @cycle_count = 0
    setup_logger(provided_logger:, log_level: Logger::INFO)

    # Queues to sync audio & rendering with the main thread
    @render_queue = Thread::Queue.new
    @audio_queue = Thread::Queue.new
    @fps_queue = Thread::Queue.new

    # GameBoy components
    load_rom(rom_path)
    @speed_limiter = SpeedLimiter.new
    @performance_timer = IntervalTimer.new
    @mmu = MMU.from_cartridge(cartridge, debug_config:)
    @cpu = CPU.new(mmu, logger:)
    @ppu = PPU.new(mmu, logger:)
    @apu = APU.new(mmu:, audio_queue:)
    @audio_sampler = AudioSampler.new(audio_queue:, logger:)
    @key_state = KeyState.new
    @screen = Screen.new(render_queue:, fps_queue:, key_state:, audio_sampler:, logger:)
  end

  def start
    register_battery_ram_saver
    register_signal_handlers

    setup_main_loop_thread
    start_audio_thread
    start_display_loop # Should be the last call in "start", as it blocks the main thread
  end

  private

  def load_rom(rom_path)
    rom_loader = RomLoader.new(rom_path)
    @cartridge = rom_loader.cartridge
    @logger.info rom_loader.description
  end

  def setup_logger(provided_logger:, log_level:)
    @logger = provided_logger || Logger.new(File::NULL)
    logger.level = log_level
    logger.formatter = proc { |s, dt, _, msg| "[#{dt.strftime('%H:%M:%S.%L')}][#{s}] #{msg}\n" }
  end

  def start_display_loop
    screen.show
  end

  def start_audio_thread
    audio_sampler.start
  end

  def register_battery_ram_saver
    return unless cartridge.with_battery?

    at_exit { BatteryRAM.save(cartridge.battery_ram_path, @mmu.external_ram) }
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

  def setup_main_loop_thread
    Thread.new do
      loop do
        @cycle_count += (nb_cycles = run_cpu_step)
        frame_pixels = ppu.tick(nb_cycles)
        apu.tick(nb_cycles)
        speed_limiter.throttle!(nb_cycles)

        # A frame needs to be rendered
        next unless frame_pixels

        # Lâche le GVL une fois par frame. Peut sinon affamer le thread display sur roms CPU-intensive.
        Thread.pass

        @render_queue << frame_pixels
        @gb_fps_counter.update
        @fps_queue << @gb_fps_counter.last_fps

        log_performance
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

    mmu.set_key_state(key_state)
    cpu.step
  end

  def log_performance
    return unless performance_timer.elapsed?

    info "Cycles: #{@cycle_count} (#{(@cycle_count / CPU::T_CYCLES_PER_SECOND.to_f).round(2)}x)"
    @cycle_count = 0
  end
end
