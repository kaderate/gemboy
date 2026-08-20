# frozen_string_literal: true

require_relative '../debug'

module Debug
  class Collector
    DEFAULT_FRAME_INTERVAL = 6

    attr_reader :frame_interval, :latest, :sequence

    def initialize(probes: {}, frame_interval: DEFAULT_FRAME_INTERVAL)
      @probes = probes
      @frame_interval = frame_interval
      @frames_since_sample = 0
      @latest = nil
      @sequence = 0
    end

    def frame_completed!
      @frames_since_sample += 1
      return nil if @frames_since_sample < frame_interval

      @frames_since_sample = 0
      sample!
    end

    # Publish order matters: a reader seeing a fresh sequence must never get a stale snapshot.
    def sample!
      snapshot = @probes.transform_values(&:snapshot)
      @latest = snapshot
      @sequence += 1
      snapshot
    end
  end
end
