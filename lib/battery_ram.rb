# frozen_string_literal: true

# BatteryRAM is a class that represents the battery-backed RAM of a Gameboy.
# The format doesn't really matter, but load and save must be fully commutative.
class BatteryRAM
  def self.load(path)
    return unless File.exist?(path)

    File.binread(path).bytes
  end

  def self.save(path, data)
    File.binwrite(path, data.pack('C*'))
  end
end
