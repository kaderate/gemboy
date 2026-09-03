# frozen_string_literal: true

# Force activation of YJIT (if available): consistently faster than ZJIT on gemboy's hot path
# (see profiling/PERFORMANCE, local, for the YJIT vs ZJIT comparison). A JIT can't be switched
# off once initialized, so a `--zjit` launch flag pre-empts this silently at the VM level --
# warn instead of quietly running slower.
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
