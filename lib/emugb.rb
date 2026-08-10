# frozen_string_literal: true

# Force activation of YJIT (if available)
RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && !RubyVM::YJIT.enabled?

require_relative 'engine'

rom_path = ARGV[0]
engine = Engine.new(rom_path)
engine.start

puts 'Done'
