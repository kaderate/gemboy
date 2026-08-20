# frozen_string_literal: true

require_relative 'rtc'

module MBC
  class BaseMBC
    attr_reader :rtc

    def initialize
      @rtc = NullRTC.new
    end
  end
end
