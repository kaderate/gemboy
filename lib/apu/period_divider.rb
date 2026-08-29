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
      @current_period_div = 0 # current period in APU clock cycles, copied from NRx3-NRx4 (11-bit)
      @next_period_div = nil
    end

    def tick(nb_ticks, initial_period_div)
      @current_period_div += (nb_ticks / @clock_divider)

      return false unless @current_period_div > PERIOD_OVERFLOW

      # Use the next period if it's set, otherwise use the current one
      if @next_period_div
        @current_period_div = @next_period_div
        @next_period_div = nil
      else
        @current_period_div = initial_period_div
      end

      true
    end

    def update_current_period_div(period_div)
      @current_period_div = period_div
    end

    def update_next_period_div(period_div)
      @next_period_div = period_div
    end
  end
end
