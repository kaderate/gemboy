# frozen_string_literal: true

require 'sdl2'
require 'rbconfig'

SDL_LIB_PREFIX = `pkg-config --variable=libdir sdl2 2>/dev/null`.strip

SDL_LIB_EXT = case RbConfig::CONFIG['host_os']
              when /darwin/ then 'dylib'
              when /linux/ then 'so'
              when /mswin|mingw|cygwin/ then 'dll'
              end

SDL_LIB = SDL_LIB_PREFIX.empty? || SDL_LIB_EXT.nil? ? nil : "#{SDL_LIB_PREFIX}/libSDL2-2.0.#{SDL_LIB_EXT}"
raise 'SDL2 not found (brew install sdl2 / apt install libsdl2-dev)' unless SDL_LIB && File.exist?(SDL_LIB)

SDL_TTF_LIB_PREFIX = `pkg-config --variable=libdir SDL2_ttf 2>/dev/null`.strip
SDL_TTF_LIB = SDL_TTF_LIB_PREFIX.empty? || SDL_LIB_EXT.nil? ? nil : "#{SDL_TTF_LIB_PREFIX}/libSDL2_ttf.#{SDL_LIB_EXT}"
raise 'SDL2_ttf not found (brew install sdl2_ttf / apt install libsdl2-ttf-dev)' unless SDL_TTF_LIB && File.exist?(SDL_TTF_LIB)

SDL.load_lib(SDL_LIB, ttf_libpath: SDL_TTF_LIB)
