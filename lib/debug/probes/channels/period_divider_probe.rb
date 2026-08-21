# frozen_string_literal: true

require 'forwardable'

module Debug
  module Probes
    module Channels
      # PeriodDividerProbe exposes the state of the period divider to the debugger
      class PeriodDividerProbe
        extend Forwardable

        def_delegators :@period_divider, :clock_divider, :current_period_div, :next_period_div

        def initialize(period_divider:)
          @period_divider = period_divider
        end

        def snapshot = { clock_divider:, current_period_div:, next_period_div: }
      end
    end
  end
end
