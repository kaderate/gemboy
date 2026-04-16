require_relative 'engine'

rom_path = ARGV[0]
engine = Engine.new(rom_path)
engine.start

puts 'Done'
