# frozen_string_literal: true

require_relative 'rtc'

module MBC
  class BaseMBC
    attr_reader :rtc

    def initialize(external_ram_start:)
      @rtc = NullRTC.new
      @external_ram_start = external_ram_start
    end
  end
end
