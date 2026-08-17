# frozen_string_literal: true

require 'sdl2'
require 'rbconfig'

# Resolves the SDL2 shared libraries at runtime, in order: GEMBOY_SDL_DIR, libraries shipped
# next to the code (vendor/sdl), usual system directories, then pkg-config as a last resort.
module SDLLoader
  class LibraryNotFound < StandardError; end

  EXT = case RbConfig::CONFIG['host_os']
        when /darwin/ then 'dylib'
        when /mswin|mingw|cygwin/ then 'dll'
        else 'so'
        end

  SDL_NAMES = ["libSDL2-2.0.#{EXT}", "libSDL2.#{EXT}", "SDL2.#{EXT}"].freeze
  TTF_NAMES = ["libSDL2_ttf-2.0.#{EXT}", "libSDL2_ttf.#{EXT}", "SDL2_ttf.#{EXT}"].freeze
  VENDOR_DIR = File.expand_path('../vendor/sdl', __dir__)
  SYSTEM_DIRS = ['/opt/homebrew/lib', '/usr/local/lib', '/usr/lib', '/usr/lib/x86_64-linux-gnu'].freeze

  class << self
    def load!
      sdl = locate(SDL_NAMES) || not_found('SDL2', 'brew install sdl2 / apt install libsdl2-dev')
      ttf = locate(TTF_NAMES) || not_found('SDL2_ttf', 'brew install sdl2_ttf / apt install libsdl2-ttf-dev')

      SDL.load_lib(sdl, ttf_libpath: ttf)
    end

    private

    def locate(names)
      first_existing(known_dirs, names) || first_existing(pkg_config_dirs, names)
    end

    def known_dirs
      [ENV.fetch('GEMBOY_SDL_DIR', nil), VENDOR_DIR, *SYSTEM_DIRS].compact
    end

    def pkg_config_dirs
      %w[sdl2 SDL2_ttf].filter_map do |pkg|
        dir = `pkg-config --variable=libdir #{pkg} 2>/dev/null`.strip
        dir unless dir.empty?
      end
    end

    def first_existing(dirs, names)
      dirs.each do |dir|
        names.each do |name|
          path = File.join(dir, name)
          return path if File.exist?(path)
        end
      end
      nil
    end

    def not_found(lib, hint)
      raise LibraryNotFound, "#{lib} not found. Set GEMBOY_SDL_DIR to the directory holding it, or install it (#{hint})"
    end
  end
end

SDLLoader.load!
