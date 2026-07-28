# frozen_string_literal: true

require_relative 'sdl_loader'

# Stores the state of the input keys
class KeyState
  def initialize
    @up = false
    @down = false
    @left = false
    @right = false
    @a = false
    @b = false
    @start = false
    @select = false
  end

  def update(key, pressed)
    case key
    when SDL::SCANCODE_UP
      @up = pressed
    when SDL::SCANCODE_DOWN
      @down = pressed
    when SDL::SCANCODE_LEFT
      @left = pressed
    when SDL::SCANCODE_RIGHT
      @right = pressed
    when SDL::SCANCODE_Z
      @a = pressed
    when SDL::SCANCODE_X
      @b = pressed
    when SDL::SCANCODE_RETURN
      @start = pressed
    when SDL::SCANCODE_SPACE
      @select = pressed
    end
  end

  def to_h
    {
      up: @up,
      down: @down,
      left: @left,
      right: @right,
      a: @a,
      b: @b,
      start: @start,
      select: @select
    }
  end

  # Getters for CPU access
  attr_reader :up, :down, :left, :right, :a, :b, :start, :select
end
