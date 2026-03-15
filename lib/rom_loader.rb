class RomLoader
  attr_accessor :rom_bytes

  def initialize(path)
    @rom_bytes = File.binread(path).bytes
  end
end
