# frozen_string_literal: true

require_relative 'register_access'

class PPU
  # NullAPU is a dummy PPU to be used by the MMU unless the real one is initialized
  class NullPPU
    include RegisterAccess

    def on_read(_addr, read_value) = read_value
    def on_write(_addr, _value); end
    def on_load(_addr, _value); end
  end
end
