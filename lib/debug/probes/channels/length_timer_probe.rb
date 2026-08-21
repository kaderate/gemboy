# frozen_string_literal: true

require 'forwardable'

module Debug
  module Probes
    module Channels
      # LengthTimerProbe exposes the state of the length timer to the debugger
      class LengthTimerProbe
        extend Forwardable

        def_delegators :@length_timer, :enabled, :length_timer, :length_timer_target, :frame_sequencer_step

        def initialize(length_timer:)
          @length_timer = length_timer
        end

        def snapshot = { enabled:, length_timer:, length_timer_target:, frame_sequencer_step: }
      end
    end
  end
end
