# frozen_string_literal: true

# Force YJIT (faster than ZJIT here); can't un-JIT once --zjit already initialized, so warn instead.
if defined?(RubyVM::YJIT) && !RubyVM::YJIT.enabled?
  RubyVM::YJIT.enable
  if !RubyVM::YJIT.enabled? && defined?(RubyVM::ZJIT) && RubyVM::ZJIT.enabled?
    warn 'gemboy: started with --zjit, but YJIT is faster here -- relaunch without --zjit for full speed'
  end
end

begin
  require_relative 'cli'

  CLI.build_with_rom.start
rescue CartridgeLoader::ROMNotFound, CartridgeLoader::UnsupportedCartridgeType, SDLLoader::LibraryNotFound => e
  warn "gemboy: #{e.message}"
  exit 1
end

puts 'Done'
