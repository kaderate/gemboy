# GameBoy DMG-01 Input Manager
module InputManager
  def button_down(id)
    key = Gosu.button_name(id)
    logger.info { "Key pressed: #{key} (id: #{id})" }
    key_state.update(key, true)
  end

  def button_up(id)
    key = Gosu.button_name(id)
    logger.info { "Key released: #{key} (id: #{id})" }
    key_state.update(key, false)
  end
end
