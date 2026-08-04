# frozen_string_literal: true

class APU
  # LengthTimer is a timer for the length of the channels
  class LengthTimer
    LENGTH_TIMER_TARGETS = [64, 64, 256, 64].freeze
    LENGTH_TIMER_STEPS = [0, 2, 4, 6].freeze

    def initialize(channel_number)
      @channel_number = channel_number
      @enabled = false
      @length_timer_target = LENGTH_TIMER_TARGETS[channel_number - 1]
      @length_timer = 0
      @frame_sequencer_step = 0
      @length_enable_was_set = false
    end

    # Direct write to NRx1 always takes effect immediately (Blargg dmg_sound 02-len_ctr test #3)
    def reload(initial_length:)
      @length_timer = @length_timer_target - initial_length
      @enabled = true
    end

    # Trigger: only reloads if the counter had expired, and in that case loads the *full* target, ignoring NRx1.
    # (Blargg dmg_sound 02-len_ctr test #6)
    def reload_if_expired
      return unless expired?

      @length_timer = @length_timer_target
      @enabled = true
    end

    def expired?
      @length_timer <= 0
    end

    def clock(step, length_enable:)
      @frame_sequencer_step = step
      return unless LENGTH_TIMER_STEPS.include?(step) && length_enable

      tick(length_enable:)
    end

    # Quirk: enabling length timer (NRx4) while the *next* DIV-APU step would not clock it applies one extra immediate decrement
    def apply_extra_clock_on_enable(length_enable:)
      newly_enabled = length_enable && !@length_enable_was_set
      @length_enable_was_set = length_enable

      return unless newly_enabled
      return if next_step_clocks?

      tick(length_enable: true)
    end

    private

    def tick(length_enable:)
      return unless length_enable && @enabled

      @length_timer -= 1 if @length_timer.positive?
      @enabled = false if expired?

      @enabled
    end

    def next_step_clocks?
      LENGTH_TIMER_STEPS.include?((@frame_sequencer_step + 1) % 8)
    end
  end
end
