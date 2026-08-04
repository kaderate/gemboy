class RomLoader
  CART_TYPES = {
    0x00 => { mbc: 0, ram: 0, battery: 0 },
    0x01 => { mbc: 1, ram: 0, battery: 0 },
    0x02 => { mbc: 1, ram: 1, battery: 0 },
    0x03 => { mbc: 1, ram: 1, battery: 1 },
    0x05 => { mbc: 2, ram: 0, battery: 0 },
    0x06 => { mbc: 2, ram: 0, battery: 1 },
    0x08 => { mbc: 0, ram: 1, battery: 0 },
    0x09 => { mbc: 0, ram: 1, battery: 1 },
    0x11 => { mbc: 3, ram: 0, battery: 0 },
    0x12 => { mbc: 3, ram: 1, battery: 0 },
    0x13 => { mbc: 3, ram: 1, battery: 1 },
    0x19 => { mbc: 5, ram: 0, battery: 0 },
    0x1A => { mbc: 5, ram: 1, battery: 0 },
    0x1B => { mbc: 5, ram: 1, battery: 1 }
    # 0x0F => 'MBC3+TIMER+BATTERY',
    # 0x10 => 'MBC3+TIMER+RAM+BATTERY',
  }.freeze
  RAM_SIZES = {
    0x00 => 'None',
    0x01 => '2KB (unofficial)',
    0x02 => '8KB',
    0x03 => '32KB (4 banks)',
    0x04 => '128KB (16 banks)',
    0x05 => '64KB (8 banks)'
  }
  BANK_SIZE = 0x4000

  attr_accessor :rom_bytes

  def initialize(path)
    @rom_bytes = File.binread(path).bytes
  end

  def cart_type = CART_TYPES[@rom_bytes[0x0147]]
  def ram_size = RAM_SIZES[@rom_bytes[0x0149]] || 'unknown'
  def rom_size = 32 * (2**@rom_bytes[0x0148]) * 1024
  def rom_bytes_size = @rom_bytes.size
  def bank_count = rom_bytes_size / BANK_SIZE

  def cart_type_mbc
    cart_type.is_a?(Hash) ? cart_type[:mbc] : 0
  end

  def cart_type_to_s
    return 'unknown' if cart_type.nil?
    return 'ROM only' if cart_type.values.all?(&:zero?)

    cart_type.reject { |_, v| v.zero? }.keys.map { _1.to_s.upcase }.join('+')
  end
end
