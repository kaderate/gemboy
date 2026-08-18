# frozen_string_literal: true

require_relative '../../lib/mbc'

RSpec.describe MBC::MBC5 do
  ROM_BANKS_MBC5 = 512 # 8MB (max MBC5) : couvre les 9 bits du registre de banque ROM

  subject(:mbc) { build_mbc5 }

  def build_mbc5(rom_bank_count: ROM_BANKS_MBC5, ram_bank_count: 4)
    build_mbc(mbc: 5, rom: build_marked_rom(bank_count: rom_bank_count), ram_bank_count:)
  end

  it 'selects a ROM bank via the low byte (0x2000-0x2FFF)' do
    mbc.write_rom(0x2000, 5)
    expect(mbc.read_rom(0x4000)).to eq(5)
  end

  it 'allows selecting bank 0 for the switchable window (no MBC1-style quirk)' do
    mbc.write_rom(0x2000, 1)
    mbc.write_rom(0x2000, 0)
    expect(mbc.read_rom(0x4000)).to eq(0)
  end

  it 'combines the low byte and the high bit (0x3000-0x3FFF) into a 9-bit bank number' do
    mbc.write_rom(0x2000, 0x34)
    mbc.write_rom(0x3000, 1)
    bank = mbc.read_rom(0x4000) | (mbc.read_rom(0x4001) << 8)
    expect(bank).to eq(0x134)
  end

  it 'switches RAM bank via the 4-bit register (0x4000-0x5FFF), independently of any mode' do
    mbc.write_rom(0x0000, 0x0A) # RAM enable

    mbc.write_rom(0x4000, 0)
    mbc.write_ram(0x0000, 0xAA)

    mbc.write_rom(0x4000, 2)
    mbc.write_ram(0x0000, 0xBB)

    mbc.write_rom(0x4000, 0)
    expect(mbc.read_ram(0x0000)).to eq(0xAA)

    mbc.write_rom(0x4000, 2)
    expect(mbc.read_ram(0x0000)).to eq(0xBB)
  end

  it 'keeps 0x0000-0x3FFF on bank 0 whatever the selected bank' do
    mbc.write_rom(0x2000, 5)
    expect(mbc.read_rom(0x0000)).to eq(0)
  end
end
