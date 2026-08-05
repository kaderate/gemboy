# frozen_string_literal: true

# RomLoader is responsible for loading the ROM file and extracting the cartridge configuration
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
  RAM_BANK_COUNTS = {
    0x00 => 0,
    0x01 => 1, # 2KB (non-officiel/rare) : arrondi à une banque pleine de 8KB
    0x02 => 1,
    0x03 => 4,
    0x04 => 16,
    0x05 => 8
  }.freeze
  ROM_BANK_SIZE = 0x4000
  RAM_BANK_SIZE = 0x2000

  CartridgeConfig = Struct.new(:mbc, :rom_declared_size, :rom_bank_count, :ram_bank_count, keyword_init: true) do
    def mbc1?
      mbc == 1
    end
  end
  Cartridge = Struct.new(:rom_bytes, :cartridge_config, keyword_init: true)

  attr_accessor :rom_bytes, :mbc, :rom_bank_count, :ram_bank_count, :rom_declared_size, :rom_loaded_size,
                :ram_size, :with_ram, :with_battery

  def initialize(path)
    @rom_bytes = File.binread(path).bytes
    @rom_loaded_size = @rom_bytes.size
    @rom_declared_size = 32 * (2**@rom_bytes[0x0148]) * 1024

    @mbc = cart_type[:mbc]
    @with_ram = cart_type[:ram].positive?
    @with_battery = cart_type[:battery].positive?

    @rom_bank_count = rom_loaded_size / ROM_BANK_SIZE
    @ram_bank_count = RAM_BANK_COUNTS[@rom_bytes[0x0149]] || 0
    @ram_size = ram_bank_count * RAM_BANK_SIZE
  end

  def cartridge
    return @cartridge if @cartridge

    cartridge_config = CartridgeConfig.new(mbc:, rom_declared_size:, rom_bank_count:, ram_bank_count:)
    @cartridge = Cartridge.new(rom_bytes:, cartridge_config:)
  end

  def description
    format('%<cart_type_summary>s: ROM loaded/total: %<rom_declared_size>d/%<rom_loaded_size>d, ' \
           'ROM banks: %<rom_bank_count>d, RAM size: %<ram_size>d',
           cart_type_summary:,
           rom_declared_size:,
           rom_loaded_size:,
           rom_bank_count:,
           ram_size:)
  end

  def cart_type_summary
    return 'ROM only' if cart_type.values.all?(&:zero?)

    cart_type.reject { |_, v| v.zero? }.keys.map { _1.to_s.upcase }.join('+')
  end

  private

  def cart_type = @cart_type ||= CART_TYPES[@rom_bytes[0x0147]]
end
