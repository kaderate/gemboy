# frozen_string_literal: true

# Save states: the emulated machine frozen into a file and brought back later.
module SaveStates
  class Error < StandardError; end

  # The file isn't a save state, or its payload can't be read back.
  class UnreadableState < Error; end
  # Written by another version of the serialized classes.
  class IncompatibleVersion < Error; end
  # Saved from another cartridge than the one running.
  class ROMMismatch < Error; end

  class UnknownSlot < Error; end
  class EmptySlot < Error; end
end
