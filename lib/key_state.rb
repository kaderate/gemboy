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
    when 'up'
      @up = pressed
    when 'down'
      @down = pressed
    when 'left'
      @left = pressed
    when 'right'
      @right = pressed
    when 'a'
      @a = pressed
    when 'b'
      @b = pressed
    when 'enter'
      @start = pressed
    when 'space'
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
