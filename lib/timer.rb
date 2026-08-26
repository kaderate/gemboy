# frozen_string_literal: true

# GameBoy DMG-01 Timer management
class Timer
  # Prescaler stores a prescaler counter and a divisor. Counter increments when prescaler counter overflows
  Prescaler = Struct.new(:counter, :pulses, :divisor, :divisor_mask, keyword_init: true) do
    def tick!(increment)
      new_pulses, self.counter = (increment + counter).divmod(divisor)
      return 0 if new_pulses.zero?

      pulses_with_overflow = (pulses + new_pulses)
      self.pulses = pulses_with_overflow & divisor_mask

      pulses_with_overflow
    end

    def set(value)
      self.pulses = value & divisor_mask
    end

    def reset_counter! = self.counter = 0
  end

  # DIVCounter handles the DIV register
  DIVCounter = Struct.new(:cycles, :initial_ticks, :initial_cycles_max, :mask, :falling_edge_bit, keyword_init: true) do
    def initialize(cycles:, initial_cycles_max:, mask:, falling_edge_bit:, initial_ticks: 0)
      super
      @prescaler = Prescaler.new(counter: cycles, pulses: initial_ticks, divisor: initial_cycles_max, divisor_mask: mask)
    end

    def tick!(increment)
      prev_ticks = @prescaler.pulses
      new_ticks = @prescaler.tick!(increment)
      compute_falling_edge(prev_ticks, new_ticks)
    end

    def set(value)
      prev_ticks = @prescaler.pulses
      @prescaler.set(value)
      @prescaler.reset_counter!
      compute_falling_edge(prev_ticks, @prescaler.pulses)
    end

    def ticks = @prescaler.pulses

    private

    def compute_falling_edge(prev_ticks, new_ticks)
      falling_edge_mask = 1 << falling_edge_bit
      @is_falling_edge = prev_ticks & falling_edge_mask != 0 && new_ticks.nobits?(falling_edge_mask)
    end
  end

  # TIMACounter handles the TIMA register
  class TIMACounter
    TAC_TO_CYCLES = [1024, 16, 64, 256].freeze

    def initialize(cycles:, initial_cycles_max:, mask:, initial_ticks: 0)
      @prescaler = Prescaler.new(counter: cycles, pulses: initial_ticks, divisor: initial_cycles_max, divisor_mask: mask)
    end

    def tick!(nb_cycles)
      new_pulses = @prescaler.tick!(nb_cycles)
      [new_pulses, new_pulses > @prescaler.divisor_mask]
    end

    def set_cycles_max_from_tac(value) = @prescaler.divisor = TAC_TO_CYCLES[value & 0x03]

    def set(value) = @prescaler.set(value)
    def ticks = @prescaler.pulses
  end

  def initialize
    @counters = {
      div_timer: DIVCounter.new(cycles: 0, initial_cycles_max: 0x100, mask: 0xFF, falling_edge_bit: 4),
      tima_timer: TIMACounter.new(cycles: 0, initial_cycles_max: 0x100, mask: 0xFF)
    }
    @tac = 0
    @tma = 0
    @falling_edges = { div: false }
  end

  # Must return true if a timer interrupt is required
  def tick!(cycles)
    increment_div_timer(cycles)
    increment_tima_timer(cycles)
  end

  def read(register)
    case register
    when :div_timer, :tima_timer
      @counters[register].ticks
    when :tma
      @tma
    when :tac
      @tac
    else
      raise "Timer register #{register} is invalid"
    end
  end

  def write(register, value, force: false)
    case register
    when :div_timer
      @falling_edges[:div] ||= @counters[:div_timer].set(force ? value : 0)
    when :tima_timer
      @counters[:tima_timer].set(value)
    when :tma
      @tma = value
    when :tac
      @tac = value
    else
      raise "Timer register #{register} is invalid"
    end
  end

  def consume_div_increment
    return false unless @falling_edges[:div]

    @falling_edges[:div] = false
    true
  end

  private

  def increment_div_timer(cycles)
    @falling_edges[:div] ||= div.tick!(cycles)
  end

  def increment_tima_timer(cycles)
    return false unless tima_timer_enabled?

    tima.set_cycles_max_from_tac(@tac)
    new_tima, tima_overflow = tima.tick!(cycles)

    # Update TMA and check for interrupt IFF overflow
    return false unless tima_overflow

    @counters[:tima_timer].set(@tma + ((new_tima - 0x100) % (0x100 - @tma)))
    true # Interrupt
  end

  def tima_timer_enabled? = @tac & 0x04 != 0
  def div = @div ||= @counters[:div_timer]
  def tima = @tima ||= @counters[:tima_timer]
end
