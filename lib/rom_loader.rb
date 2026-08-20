# frozen_string_literal: true

require_relative 'mbc'
require_relative 'mbc/external_ram'
require_relative 'mbc/constants'

# RomLoader is responsible for loading the ROM file and extracting the cartridge configuration
class RomLoader
  class ROMNotFound < StandardError; end
  class UnsupportedCartridgeType < StandardError; end

  CART_TYPES = {
    0x00 => { mbc: 0, ram: 0, battery: 0, timer: 0 },
    0x01 => { mbc: 1, ram: 0, battery: 0, timer: 0 },
    0x02 => { mbc: 1, ram: 1, battery: 0, timer: 0 },
    0x03 => { mbc: 1, ram: 1, battery: 1, timer: 0 },
    0x05 => { mbc: 2, ram: 0, battery: 0, timer: 0 },
    0x06 => { mbc: 2, ram: 0, battery: 1, timer: 0 },
    0x08 => { mbc: 0, ram: 1, battery: 0, timer: 0 },
    0x09 => { mbc: 0, ram: 1, battery: 1, timer: 0 },
    0x11 => { mbc: 3, ram: 0, battery: 0, timer: 0 },
    0x12 => { mbc: 3, ram: 1, battery: 0, timer: 0 },
    0x13 => { mbc: 3, ram: 1, battery: 1, timer: 0 },
    0x19 => { mbc: 5, ram: 0, battery: 0, timer: 0 },
    0x1A => { mbc: 5, ram: 1, battery: 0, timer: 0 },
    0x1B => { mbc: 5, ram: 1, battery: 1, timer: 0 },
    0x0F => { mbc: 3, ram: 0, battery: 1, timer: 1 },
    0x10 => { mbc: 3, ram: 1, battery: 1, timer: 1 }
  }.freeze
  RAM_BANK_COUNTS = {
    0x00 => 0,
    0x01 => 1, # 2KB (non-officiel/rare) : arrondi à une banque pleine de 8KB
    0x02 => 1,
    0x03 => 4,
    0x04 => 16,
    0x05 => 8
  }.freeze

  CartridgeConfig = Struct.new(:mbc, :rom_declared_size, :rom_bank_count, :ram_bank_count, :with_battery, :with_timer,
                               keyword_init: true) do
    def with_battery? = with_battery
    def with_timer? = with_timer
  end

  Cartridge = Struct.new(:rom_path, :name, :rom_bytes, :cartridge_config, keyword_init: true) do
    def with_battery? = cartridge_config.with_battery?
    def with_timer? = cartridge_config.with_timer?
    def battery_ram_path = cartridge_config.with_battery? ? Pathname.new(rom_path).sub_ext('.sav').to_s : nil
  end

  attr_accessor :rom_bytes, :name, :mbc, :rom_bank_count, :ram_bank_count, :rom_declared_size, :rom_loaded_size,
                :ram_size, :with_battery, :with_timer, :rom_path

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
    @with_timer = cart_type[:timer].positive?

    @rom_bank_count = rom_loaded_size / MBC::Constants::ROM_BANK_SIZE
    @ram_bank_count = RAM_BANK_COUNTS[@rom_bytes[0x0149]] || 0
    @ram_size = ram_bank_count * MBC::Constants::RAM_BANK_SIZE
  end

  def cartridge
    return @cartridge if @cartridge

    cartridge_config = CartridgeConfig.new(mbc:, rom_declared_size:, rom_bank_count:, ram_bank_count:, with_battery:, with_timer:)
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
    parts << 'TIMER' if cart_type[:timer].positive?
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
