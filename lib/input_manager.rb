# GameBoy DMG-01 Input Manager
module InputManager
  def button_down(id)
    key = Gosu.button_name(id)
    logger.warn { "Key pressed: #{key} (id: #{id})" }
    key_state.update(id, true)
  end

  def button_up(id)
    key = Gosu.button_name(id)
    logger.warn { "Key released: #{key} (id: #{id})" }
    key_state.update(id, false)
  end
end
