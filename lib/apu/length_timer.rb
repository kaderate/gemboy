# frozen_string_literal: true

class APU
  # LengthTimer is a timer for the length of the channels
  class LengthTimer
    LENGTH_TIMER_TARGETS = [64, 64, 256, 64].freeze

    def initialize(channel_number)
      @channel_number = channel_number
      @length_timer_target = LENGTH_TIMER_TARGETS[channel_number - 1]
      @length_timer = 0
    end

    def tick(length_enable:)
      return unless length_enable && @enabled

      @length_timer -= 1 if @length_timer.positive?
      @enabled = false if expired?

      @enabled
    end

    def reset(initial_length:, force: false)
      return if !force && !expired?

      @length_timer = @length_timer_target - initial_length
      @enabled = true
    end

    def expired?
      @length_timer <= 0
    end
  end
end
