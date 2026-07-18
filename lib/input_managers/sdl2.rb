# GameBoy DMG-01 Input Manager for SDL2
module InputManagers
  module SDL2
    def key_pressed(event)
      kb    = SDL::KeyboardEvent.new(event)
      scan  = kb[:keysym][:scancode]
      state = kb[:type] == SDL::KEYDOWN
      logger&.info { "Key #{state ? 'pressed' : 'released'}: scancode=#{scan}" }
      key_state.update(scan, state)
    end
  end
end
