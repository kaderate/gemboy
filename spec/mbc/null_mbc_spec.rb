# frozen_string_literal: true

require_relative '../../lib/mbc'

RSpec.describe MBC::NullMBC do
  describe 'ROM' do
    it 'reads the whole 0x0000-0x7FFF window straight from the ROM bytes' do
      rom = build_rom
      rom[0x0000] = 0xAB
      rom[0x7FFF] = 0xCD
      mbc = build_mbc(rom:)

      expect(mbc.read_rom(0x0000)).to eq(0xAB)
      expect(mbc.read_rom(0x7FFF)).to eq(0xCD)
    end

    it 'ignores writes to the ROM area (no banking register)' do
      mbc = build_mbc
      mbc.write_rom(0x2000, 0x05)

      expect(mbc.read_rom(0x4000)).to eq(0x00)
    end
  end

  describe 'external RAM (cart_type 0x08/0x09, ROM+RAM)' do
    it 'is accessible without any enable sequence when the cartridge has RAM' do
      mbc = build_mbc(ram_bank_count: 1)
      mbc.write_ram(0x0000, 0x42)

      expect(mbc.read_ram(0x0000)).to eq(0x42)
    end

    it 'stays at 0xFF when the cartridge declares no RAM at all' do
      mbc = build_mbc(ram_bank_count: 0)
      mbc.write_ram(0x0000, 0x42)

      expect(mbc.read_ram(0x0000)).to eq(0xFF)
    end
  end
end
