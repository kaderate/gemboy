# frozen_string_literal: true

class PPU
  # Rising-edge detector over successive boolean samples.
  class EdgeDetector
    def initialize
      @state = false
    end

    def rising?(current)
      edge = current && !@state
      @state = current
      edge
    end
  end
end
