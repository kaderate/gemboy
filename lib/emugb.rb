# frozen_string_literal: true

# Force activation of YJIT (if available)
RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && !RubyVM::YJIT.enabled?

begin
  require_relative 'engine'

  Engine.build_with_rom.start
rescue RomLoader::ROMNotFound, RomLoader::UnsupportedCartridgeType, SDLLoader::LibraryNotFound => e
  warn "gemboy: #{e.message}"
  exit 1
end

puts 'Done'
