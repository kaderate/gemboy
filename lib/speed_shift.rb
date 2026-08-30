# frozen_string_literal: true

# A speed shifter
class SpeedShift
  attr_reader :armed, :double_speed

  def initialize
    @double_speed = false
    @armed = false
  end

  def arm!(value)
    @armed = value.odd?
  end

  def switch_speed!
    return unless @armed

    @double_speed = !@double_speed
    @armed = false
  end

  def shift = @double_speed ? 1 : 0

  def key1_register = (shift << 7) | armed_bit
  def armed_bit = @armed ? 1 : 0
end
