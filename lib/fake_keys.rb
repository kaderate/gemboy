# frozen_string_literal: true

# Headless input source for driving Joypad#key_state without SDL (profiling scripts, Driver).
class FakeKeys
  attr_accessor :up, :down, :left, :right, :a, :b, :start, :select

  def initialize = clear
  def clear = @up = @down = @left = @right = @a = @b = @start = @select = false
  def press(key) = send("#{key}=", true)
end
