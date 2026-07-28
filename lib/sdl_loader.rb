# frozen_string_literal: true

require 'sdl2'

SDL_LIB_PREFIX = `pkg-config --variable=libdir sdl2 2>/dev/null`.strip
SDL_LIB = SDL_LIB_PREFIX.empty? ? nil : "#{SDL_LIB_PREFIX}/libSDL2-2.0.0.dylib"
raise 'SDL2 not found (brew install sdl2)' unless SDL_LIB && File.exist?(SDL_LIB)

SDL.load_lib(SDL_LIB)
