# frozen_string_literal: true

module Debug
  module Probes
    # DMAProbe exposes the state of the GDMA/HDMA controller to the debugger
    class DMAProbe
      def initialize(dma:)
        @dma = dma
      end

      def snapshot
        {
          mode: @dma.mode.zero? ? 'GDMA' : 'HDMA',
          active: @dma.transfer_active,
          source: @dma.source,
          destination: @dma.destination,
          requested_blocks: @dma.transfer_length + 1,
          remaining_blocks: @dma.transfer_active ? @dma.transfer_rev_counter : 0
        }
      end
    end
  end
end
