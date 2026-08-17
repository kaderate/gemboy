# frozen_string_literal: true

require 'tmpdir'
require_relative '../lib/sdl_loader'

RSpec.describe SDLLoader do
  describe '.first_existing' do
    it 'returns the first name found, scanning directories in order' do
      Dir.mktmpdir do |first|
        Dir.mktmpdir do |second|
          FileUtils.touch(File.join(second, 'libSDL2.dylib'))

          found = described_class.send(:first_existing, [first, second], ['libSDL2.dylib'])
          expect(found).to eq(File.join(second, 'libSDL2.dylib'))
        end
      end
    end

    it 'tries every candidate name within a directory' do
      Dir.mktmpdir do |dir|
        FileUtils.touch(File.join(dir, 'libSDL2.dylib'))

        found = described_class.send(:first_existing, [dir], ['libSDL2-2.0.dylib', 'libSDL2.dylib'])
        expect(found).to eq(File.join(dir, 'libSDL2.dylib'))
      end
    end

    it 'returns nil when nothing matches' do
      Dir.mktmpdir do |dir|
        expect(described_class.send(:first_existing, [dir], ['libSDL2.dylib'])).to be_nil
      end
    end
  end

  describe '.known_dirs' do
    it 'puts GEMBOY_SDL_DIR first, before the vendored and system directories' do
      allow(ENV).to receive(:fetch).with('GEMBOY_SDL_DIR', nil).and_return('/custom/sdl')

      expect(described_class.send(:known_dirs).first).to eq('/custom/sdl')
    end

    it 'falls back to the vendored directory when GEMBOY_SDL_DIR is unset' do
      allow(ENV).to receive(:fetch).with('GEMBOY_SDL_DIR', nil).and_return(nil)

      expect(described_class.send(:known_dirs).first).to eq(SDLLoader::VENDOR_DIR)
    end
  end

  describe 'library names' do
    it 'lists candidates for the current platform extension' do
      expect(SDLLoader::SDL_NAMES).to all(end_with(".#{SDLLoader::EXT}"))
      expect(SDLLoader::TTF_NAMES).to all(end_with(".#{SDLLoader::EXT}"))
    end
  end

  describe '.not_found' do
    it 'raises LibraryNotFound mentioning the override variable' do
      expect { described_class.send(:not_found, 'SDL2', 'brew install sdl2') }
        .to raise_error(SDLLoader::LibraryNotFound, /GEMBOY_SDL_DIR/)
    end
  end
end
