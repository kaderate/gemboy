class RomLoader
  CART_TYPES = {
    0x00 => 'ROM ONLY',
    0x01 => 'MBC1',
    0x02 => 'MBC1+RAM',
    0x03 => 'MBC1+RAM+BATTERY',
    0x05 => 'MBC2',
    0x06 => 'MBC2+BATTERY',
    0x08 => 'ROM+RAM',
    0x09 => 'ROM+RAM+BATTERY',
    0x0F => 'MBC3+TIMER+BATTERY',
    0x10 => 'MBC3+TIMER+RAM+BATTERY',
    0x11 => 'MBC3',
    0x12 => 'MBC3+RAM',
    0x13 => 'MBC3+RAM+BATTERY',
    0x19 => 'MBC5',
    0x1A => 'MBC5+RAM',
    0x1B => 'MBC5+RAM+BATTERY'
  }.freeze
  RAM_SIZES = {
    0x00 => 'None',
    0x01 => '2KB (unofficial)',
    0x02 => '8KB',
    0x03 => '32KB (4 banks)',
    0x04 => '128KB (16 banks)',
    0x05 => '64KB (8 banks)'
  }

  attr_accessor :rom_bytes

  def initialize(path)
    @rom_bytes = File.binread(path).bytes
  end

  def cart_type = CART_TYPES[@rom_bytes[0x0147]] || 'unknown'
  def ram_size = RAM_SIZES[@rom_bytes[0x0149]] || 'unknown'
  def rom_size = 32 * (2**@rom_bytes[0x0148]) * 1024
  def rom_bytes_size = @rom_bytes.size
end
