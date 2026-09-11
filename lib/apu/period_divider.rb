# frozen_string_literal: true

class APU
  # PeriodDivider handles period management for a channel
  class PeriodDivider
    PERIOD_OVERFLOW = 0x7FF
    CLOCK_DIVIDERS = [4, 4, 2, 4].freeze

    attr_reader :clock_divider, :current_period_div, :next_period_div

    def initialize(channel_number)
      @channel_number = channel_number
      @clock_divider = CLOCK_DIVIDERS[channel_number - 1]
      # CLOCK_DIVIDERS are powers of two: shift/mask replace the per-tick division and modulo
      @clock_divider_shift = @clock_divider.bit_length - 1
      @clock_divider_mask = @clock_divider - 1
      @current_period_div = 0 # current period in APU clock cycles, copied from NRx3-NRx4 (11-bit)
      @current_period_div_accumulator = 0
      @next_period_div = nil
    end

    def tick(nb_ticks, initial_period_div)
      increment_period_div!(nb_ticks)
      return false unless overflowed?

      handle_overflow!(initial_period_div)
      true
    end

    def update_current_period_div(period_div)
      @current_period_div = period_div
    end

    def update_next_period_div(period_div)
      @next_period_div = period_div
    end

    private

    def increment_period_div!(nb_ticks)
      @current_period_div_accumulator += nb_ticks
      @current_period_div += @current_period_div_accumulator >> @clock_divider_shift
      @current_period_div_accumulator &= @clock_divider_mask
    end

    def handle_overflow!(initial_period_div)
      excess = @current_period_div - (PERIOD_OVERFLOW + 1)
      # Use the next period if it's set, otherwise use the current one
      @current_period_div = (@next_period_div || initial_period_div) + excess
      @next_period_div = nil
    end

    def overflowed? = @current_period_div > PERIOD_OVERFLOW
  end
end
