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
    when Gosu::KB_UP
      @up = pressed
    when Gosu::KB_DOWN
      @down = pressed
    when Gosu::KB_LEFT
      @left = pressed
    when Gosu::KB_RIGHT
      @right = pressed
    when Gosu::KB_A
      @a = pressed
    when Gosu::KB_B
      @b = pressed
    when Gosu::KB_RETURN
      @start = pressed
    when Gosu::KB_SPACE
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
