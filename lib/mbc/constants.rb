# frozen_string_literal: true

module MBC
  # Constants for the MBC chips
  module Constants
    ROM_BANK_START = 0x4000 # To identify ROM banks VS ROM
    ROM_BANK_SIZE = 0x4000
    RAM_BANK_SIZE = 0x2000

    CYCLES_PER_SECOND = 4_194_304
  end
end
