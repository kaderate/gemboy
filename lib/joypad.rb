# frozen_string_literal: true

# GameBoy DMG-01 Joypad
class Joypad
  attr_accessor :key_state

  def initialize
    @key_state = nil
    @inputs_selector = nil # nil, :direction, ou :button
  end

  def read
    return 0xFF if key_state.nil? # Pas d'entrée, tous les bits sont à 1

    result = 0xFF
    if @inputs_selector == :direction || @inputs_selector == :both
      result &= ~0x01 if key_state.right
      result &= ~0x02 if key_state.left
      result &= ~0x04 if key_state.up
      result &= ~0x08 if key_state.down
    end
    if @inputs_selector == :button || @inputs_selector == :both
      result &= ~0x01 if key_state.a
      result &= ~0x02 if key_state.b
      result &= ~0x04 if key_state.select
      result &= ~0x08 if key_state.start
    end
    result
  end

  def write(value)
    direction_selected = value & 0x10 == 0
    button_selected = value & 0x20 == 0
    @inputs_selector = if direction_selected && button_selected
                         :both
                       elsif direction_selected
                         :direction
                       elsif button_selected
                         :button
                       end
  end
end
