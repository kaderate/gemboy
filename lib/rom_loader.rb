# frozen_string_literal: true

# RomLoader is responsible for loading the ROM file and extracting the cartridge configuration
class RomLoader
  class ROMNotFound < StandardError; end
  class UnsupportedCartridgeType < StandardError; end

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

  CartridgeConfig = Struct.new(:mbc, :rom_declared_size, :rom_bank_count, :ram_bank_count, :with_battery, keyword_init: true) do
    def mbc1?
      mbc == 1
    end

    def mbc5?
      mbc == 5
    end

    def with_battery?
      with_battery
    end
  end

  DEFAULT_CARTRIDGE_CONFIG = CartridgeConfig.new(mbc: 0, rom_declared_size: 0, rom_bank_count: 1, ram_bank_count: 0).freeze

  Cartridge = Struct.new(:rom_path, :name, :rom_bytes, :cartridge_config, keyword_init: true) do
    def battery_ram_path
      return nil unless cartridge_config.with_battery?

      Pathname.new(rom_path).sub_ext('.sav').to_s
    end

    def with_battery?
      cartridge_config.with_battery?
    end
  end

  attr_accessor :rom_bytes, :name, :mbc, :rom_bank_count, :ram_bank_count, :rom_declared_size, :rom_loaded_size,
                :ram_size, :with_battery, :rom_path

  def initialize(path)
    @rom_path = path
    validate_rom_exists!

    @rom_bytes = File.binread(path).bytes
    validate_cart_type!

    @rom_loaded_size = @rom_bytes.size
    @rom_declared_size = 32 * (2**@rom_bytes[0x0148]) * 1024

    @name = @rom_bytes[0x0134..0x0143].pack('C*')

    @mbc = cart_type[:mbc]
    @with_battery = cart_type[:battery].positive?

    @rom_bank_count = rom_loaded_size / ROM_BANK_SIZE
    @ram_bank_count = RAM_BANK_COUNTS[@rom_bytes[0x0149]] || 0
    @ram_size = ram_bank_count * RAM_BANK_SIZE
  end

  def cartridge
    return @cartridge if @cartridge

    cartridge_config = CartridgeConfig.new(mbc:, rom_declared_size:, rom_bank_count:, ram_bank_count:, with_battery:)
    @cartridge = Cartridge.new(rom_path:, name:, rom_bytes:, cartridge_config:)
  end

  def description
    format('%<name>s: type: %<cart_type_summary>s (%<cart_type_bytes>#X), ROM loaded/total: ' \
           '%<rom_declared_size>d/%<rom_loaded_size>d, ROM banks: %<rom_bank_count>d, RAM size: %<ram_size>d',
           name:,
           cart_type_summary:,
           cart_type_bytes:,
           rom_declared_size:,
           rom_loaded_size:,
           rom_bank_count:,
           ram_size:)
  end

  def cart_type_summary
    return 'ROM only' if cart_type.values.all?(&:zero?)

    parts = [mbc.zero? ? 'ROM' : "MBC#{mbc}"]
    parts << 'RAM' if cart_type[:ram].positive?
    parts << 'BATTERY' if cart_type[:battery].positive?
    parts.join('+')
  end

  private

  def validate_rom_exists!
    raise ROMNotFound, "ROM file not found: #{rom_path}" unless File.exist?(rom_path)
  end

  def validate_cart_type!
    return if CART_TYPES.key?(cart_type_bytes)

    raise UnsupportedCartridgeType,
          format('Unsupported cartridge type 0x%<byte>02X in %<path>s', byte: cart_type_bytes, path: rom_path)
  end

  def cart_type = @cart_type ||= CART_TYPES[cart_type_bytes]
  def cart_type_bytes = @rom_bytes[0x0147]
end
