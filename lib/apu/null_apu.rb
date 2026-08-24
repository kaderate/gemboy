# frozen_string_literal: true

require_relative 'register_access'

class APU
  # NullAPU is a dummy APU to be used by the MMU unless the real APU is initialized
  class NullAPU
    class DummyChannel
      def on_write(_addr, _value); end
      def on_load(_addr, _value); end
    end

    include RegisterAccess

    def initialize
      super
      @dummy_channel = DummyChannel.new
    end

    def handler_for_addr(_addr) = @dummy_channel
  end
end
