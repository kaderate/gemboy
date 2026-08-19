# frozen_string_literal: true

require_relative 'mbc/null_mbc'
require_relative 'mbc/mbc1'
require_relative 'mbc/mbc3'
require_relative 'mbc/mbc5'

# The MBC module is responsible for handling the memory bank controllers
module MBC
  class UnsupportedMBC < StandardError; end

  def self.build(cartridge)
    mbc = cartridge.cartridge_config.mbc

    case mbc
    when 0 then NullMBC.new(cartridge)
    when 1 then MBC1.new(cartridge)
    when 3 then MBC3.new(cartridge)
    when 5 then MBC5.new(cartridge)
    else
      raise UnsupportedMBC, "Unsupported MBC type: #{mbc}"
    end
  end
end
