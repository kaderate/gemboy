# frozen_string_literal: true

require_relative '../cpu'

# Use an absolute sequence (and not relative) to avoid drifts
class SpeedLimiter
  CYCLES_PER_SLICE = 70_224 # Arbitrary (here, nb cycles per frame), sized to avoid sleeping too often
  SLICE_DURATION_SEC = CYCLES_PER_SLICE.to_f / CPU::T_CYCLES_PER_SECOND
  SLICE_SKIP_COUNT = 5

  attr_reader :slice_count, :sleep_time

  def initialize
    @base_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @slice_count = 0 # A slice is a unit of emulated time, used to clock the limiter
    @cycle_count = 0
    @sleep_time = nil
  end

  def throttle!(nb_cycles)
    @cycle_count += nb_cycles
    return unless cycle_count_reached?

    reset_cycle_count!
    tick_slice!
    compute_sleep_time
    adjust_drift!
    sleep(sleep_time) if sleep_time.positive?
  end

  private

  def cycle_count_reached? = @cycle_count >= CYCLES_PER_SLICE
  def reset_cycle_count! = @cycle_count = 0

  def adjust_drift!
    return unless sleep_time <= -(SLICE_SKIP_COUNT * SLICE_DURATION_SEC)

    skipped_slices = (sleep_time.abs / SLICE_DURATION_SEC).floor
    @base_time += skipped_slices * SLICE_DURATION_SEC

    # Recompute sleep time to account for the drift
    compute_sleep_time

    nil # YJIT: same return value for all paths
  end

  def tick_slice! = @slice_count += 1
  def compute_sleep_time = @sleep_time = slice_schedule - Process.clock_gettime(Process::CLOCK_MONOTONIC)
  def slice_schedule = @base_time + (@slice_count * SLICE_DURATION_SEC)
end
