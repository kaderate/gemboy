# frozen_string_literal: true

require 'forwardable'

module Debug
  module Probes
    module Channels
      # VolumeEnvelopeProbe exposes the state of the volume envelope to the debugger
      class VolumeEnvelopeProbe
        extend Forwardable

        def_delegators :@volume_envelope, :volume, :envelope_sweep_step

        def initialize(volume_envelope:)
          @volume_envelope = volume_envelope
        end

        def snapshot = { volume:, envelope_sweep_step: }
      end
    end
  end
end
