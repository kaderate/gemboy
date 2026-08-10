# frozen_string_literal: true

# Utilise un séquencement absolu (et non relatif) pour éviter des décalages
class FrameLimiter
  TARGET_GB_FPS = 59.7
  TARGET_FRAME_DURATION_SEC = 1.0 / TARGET_GB_FPS
  FRAME_SKIP_COUNT = 5

  attr_reader :frame_count, :sleep_time

  def initialize
    @base_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @frame_count = 0
    @sleep_time = nil
  end

  def limit_frames_per_second!
    tick_frame!
    compute_sleep_time
    adjust_drift!
    sleep(sleep_time) if sleep_time.positive?
  end

  private

  def adjust_drift!
    return unless sleep_time <= -(FRAME_SKIP_COUNT * TARGET_FRAME_DURATION_SEC)

    skipped_frames = (sleep_time.abs / TARGET_FRAME_DURATION_SEC).floor
    @base_time += skipped_frames * TARGET_FRAME_DURATION_SEC

    # Recompute sleep time to account for the drift
    compute_sleep_time

    nil # YJIT: same return value for all paths
  end

  def tick_frame! = @frame_count += 1
  def compute_sleep_time = @sleep_time = frame_schedule - Process.clock_gettime(Process::CLOCK_MONOTONIC)
  def frame_schedule = @base_time + (@frame_count * TARGET_FRAME_DURATION_SEC)
end
