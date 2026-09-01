# frozen_string_literal: true

# Force activation of YJIT (if available)
RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && !RubyVM::YJIT.enabled?

require 'io/console'
require 'io/wait'
require 'fileutils'
require_relative '../profiling/utils'

class HeadlessEmulator
  DEFAULT_MAX_SECONDS = 20
  CYCLE_PER_SEC = CPU::T_CYCLES_PER_SECOND
  SCREENSHOT_DIR = 'tmp'
  LOG_STRING = '[%<time>s] %<step>d: %<label>-5s @ %<elapsed_time>3.2fs (next @ %<next_tick>3.2fs)'
  CHAFA_ARGS = ['--size', '64x32'].freeze
  CHAFA_SYMBOLS_ARGS = ['--format', 'symbols'].freeze

  # chafa reads on stdin so any concurrent reader steals it some bytes required to make it work. Hence the polling.
  class Keyboard
    POLL_INTERVAL_CYCLES = 70_224

    def initialize
      @enabled = $stdin.tty?
      return unless @enabled

      @next_poll_cycle = POLL_INTERVAL_CYCLES
      $stdin.raw!(intr: true)
      at_exit { restore }
    end

    def key_at(cycle)
      return unless @enabled && cycle >= @next_poll_cycle

      @next_poll_cycle = cycle + POLL_INTERVAL_CYCLES
      return unless wait_readable

      read_nonblock(1).to_s.downcase
    end

    # to avoid messing with chafa
    def drain
      nil while @enabled && wait_readable && read_nonblock(4096).is_a?(String)
    end

    def restore
      return unless @enabled

      @enabled = false
      $stdin.cooked!
    end

    private

    def read_nonblock(size) = $stdin.read_nonblock(size, exception: false)
    def wait_readable = $stdin.wait_readable(0)
  end

  attr_reader :cpu, :ppu, :apu, :mmu, :cartridge, :speed_limiter, :keys, :total_cycle, :current_key_index, :next_tick,
              :screenshot_format, :input_sequence, :keyboard

  def initialize(path:, input_sequence:, screenshot_format: :image, max_seconds: DEFAULT_MAX_SECONDS, with_limiter: false)
    raise ArgumentError, 'Unknown screenshot format' unless %i[image symbols].include?(screenshot_format)
    unless input_sequence.is_a?(Array) && input_sequence.all?(Array)
      raise ArgumentError, 'Input sequence must be an array of pairs'
    end

    @screenshot_format = screenshot_format
    @max_cycles = max_seconds * CYCLE_PER_SEC
    @input_sequence = input_sequence
    @cpu, @ppu, @apu, @mmu, @keys, @cartridge, @speed_limiter = build_emulator(path, with_input: true, with_limiter:)

    @total_cycle = 0
    @current_key_index = 0
    @key_pressed = false
    @next_tick = 0

    FileUtils.mkdir_p(SCREENSHOT_DIR)

    @keyboard = Keyboard.new
  end

  def start
    print_shortcuts

    loop do
      @total_cycle = total_cycle + run_steps(cpu, ppu, apu, 10, speed_limiter)

      handle_shortcut
      handle_input(keys)

      break if total_cycle >= @max_cycles || (no_more_input? && elapsed_time >= next_tick)
    end

    display_screenshot(:final)
    puts format('no crash after %<time>.2fs', time: elapsed_time)
    true
  rescue StandardError => e
    begin
      display_screenshot(:crash)
    rescue StandardError => screenshot_error
      puts "(could not capture the crash screenshot: #{screenshot_error.class})"
    end
    puts format('CRASH after %<elapsed_time>.2fs: %<class>s: %<message>s', elapsed_time:, class: e.class, message: e.message)
    puts e.backtrace
    false
  ensure
    keyboard.restore
  end

  private

  def print_shortcuts = puts "Shortcuts:\n  s: take a screenshot\n  q: quit\n\n"

  def handle_shortcut
    case keyboard.key_at(total_cycle)
    when 's' then display_screenshot('User Requested')
    when 'q' then quit
    end
  end

  def quit
    keyboard.restore
    puts 'Quitting...'
    exit
  end

  def handle_input(keys)
    return unless ready_for_next_input?

    input_label = set_input(keys)
    display_screenshot("#{input_sequence[current_key_index - 1]&.first} (#{input_label || 'N/A'})")
  end

  def set_input(keys)
    key, duration, label = input_sequence[current_key_index]

    case key
    when :wait
      if @key_pressed
        @key_pressed = false
        keys.clear
      end
    when :start, :a, :b, :select, :up, :down, :left, :right
      keys.press(key)
      @key_pressed = true
    else
      raise "Unknown key: #{key.inspect}"
    end

    @next_tick += duration || 1
    @current_key_index += 1
    label
  end

  def display_screenshot(label)
    path = File.join(SCREENSHOT_DIR, format('screen_%<rom_name>s_%<total_cycle>08d.png', rom_name:, total_cycle:))
    ppu.export_framebuffer_png(path)

    puts format(LOG_STRING, step: current_key_index, label:, elapsed_time:, time: Time.now.strftime('%H:%M:%S.%L'),
                            next_tick:)

    chafa_args = screenshot_format == :symbols ? CHAFA_ARGS + CHAFA_SYMBOLS_ARGS : CHAFA_ARGS

    if system('chafa', *chafa_args, path)
      keyboard.drain
      puts '-' * 64
      return
    end

    puts '(chafa not found: brew install chafa)'
  end

  def no_more_input? = current_key_index >= input_sequence.size
  def ready_for_next_input? = current_key_index < input_sequence.size && elapsed_time >= next_tick
  def rom_name = @rom_name ||= cartridge.name.gsub(/[^A-Za-z0-9]/, '')
  def elapsed_time = total_cycle.to_f / CYCLE_PER_SEC
end
