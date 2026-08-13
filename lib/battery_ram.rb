# frozen_string_literal: true

# BatteryRAM is a class that represents the battery-backed RAM of a Gameboy.
# The format doesn't really matter, but load and save must be fully commutative.
class BatteryRAM
  BatteryRAMConfig = Struct.new(:saved_ram, :battery_ram_path, keyword_init: true)

  def self.load(path)
    saved_ram = File.binread(path).bytes if File.exist?(path)

    BatteryRAMConfig.new(saved_ram:, battery_ram_path: path)
  end

  def self.save(path, data)
    File.binwrite(path, data.pack('C*'))
  end
end
