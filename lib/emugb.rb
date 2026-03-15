require_relative 'engine'

rom_path = ARGV[0]
puts rom_path
engine = Engine.new(rom_path)
engine.run

puts 'Done'
