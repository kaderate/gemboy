# frozen_string_literal: true

require_relative 'mbc/null_mbc'
require_relative 'mbc/mbc1'
require_relative 'mbc/mbc2'
require_relative 'mbc/mbc3'
require_relative 'mbc/mbc5'

# The MBC module is responsible for handling the memory bank controllers
module MBC
  class UnsupportedMBC < StandardError; end

  def self.build(cartridge, external_ram_start: 0xA000)
    mbc = cartridge.cartridge_config.mbc

    case mbc
    when 0 then NullMBC.new(cartridge, external_ram_start:)
    when 1 then MBC1.new(cartridge, external_ram_start:)
    when 2 then MBC2.new(cartridge, external_ram_start:)
    when 3 then MBC3.new(cartridge, external_ram_start:)
    when 5 then MBC5.new(cartridge, external_ram_start:)
    else
      raise UnsupportedMBC, "Unsupported MBC type: #{mbc}"
    end
  end
end
