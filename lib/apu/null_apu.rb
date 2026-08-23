# frozen_string_literal: true

require_relative 'register_access'

class APU
  # NullAPU is a dummy APU to be used by the MMU unless the real APU is initialized
  class NullAPU
    include RegisterAccess
  end
end
