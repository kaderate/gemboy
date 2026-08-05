# GameBoy DMG-01 Input Manager for SDL2
module InputManagers
  module SDL2
    def key_pressed(event)
      kb    = SDL::KeyboardEvent.new(event)
      scan  = kb[:keysym][:scancode]
      state = kb[:type] == SDL::KEYDOWN
      logger&.debug { "Key #{state ? 'pressed' : 'released'}: scancode=#{scan}" }

      toggle_vernier_profile if scan == SDL::SCANCODE_F1 && state

      key_state.update(scan, state)
    end

    # Debug : F1 démarre/arrête un profil Vernier en direct sur la partie en cours, pour
    # capturer une scène précise (ex: ralentissement reproductible seulement en jeu) sans
    # avoir à la reproduire dans un script headless.
    def toggle_vernier_profile
      require 'vernier'

      if @vernier_profiling
        out = Vernier.stop_profile
        @vernier_profiling = false
        puts "[vernier] profil arrêté, écrit dans #{out.meta[:out]}"
      else
        out_path = "profiling/live-#{Time.now.strftime('%Y%m%d-%H%M%S')}.json"
        Vernier.start_profile(out: out_path, allocation_interval: 1000)
        @vernier_profiling = true
        puts "[vernier] profil démarré -> #{out_path}"
      end
    rescue LoadError
      puts '[vernier] gem non disponible (bundle install manquant ?)'
    end
  end
end
