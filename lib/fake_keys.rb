# frozen_string_literal: true

# Headless input source for driving Joypad#key_state without SDL (profiling scripts, Driver).
class FakeKeys
  attr_accessor :up, :down, :left, :right, :a, :b, :start, :select

  def initialize = clear
  def clear = @up = @down = @left = @right = @a = @b = @start = @select = false

  def press(key)
    case key.to_sym
    when :up then @up = true
    when :down then @down = true
    when :left then @left = true
    when :right then @right = true
    when :a then @a = true
    when :b then @b = true
    when :start then @start = true
    when :select then @select = true
    else raise ArgumentError, "unknown key: #{key}"
    end
  end
end
