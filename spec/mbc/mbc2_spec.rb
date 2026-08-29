# frozen_string_literal: true

require 'tmpdir'
require_relative '../../lib/mbc'

RSpec.describe MBC::MBC2 do
  ROM_BANKS_MBC2 = 16 # 256KB (max MBC2)

  subject(:mbc) { build_mbc2 }

  def build_mbc2(rom_bank_count: ROM_BANKS_MBC2, **) = build_mbc(mbc: 2, rom: build_marked_rom(bank_count: rom_bank_count), **)

  def enable_ram = mbc.write_rom(0x0000, 0x0A)

  describe 'ROM bank select (bit 8 of the write address set, 4 bits)' do
    it 'selects the given bank for the 0x4000-0x7FFF window' do
      mbc.write_rom(0x2100, 5)
      expect(mbc.read_rom(0x4000)).to eq(5)
    end

    it 'maps bank 0 to bank 1 (hardware quirk)' do
      mbc.write_rom(0x2100, 0)
      expect(mbc.read_rom(0x4000)).to eq(1)
    end

    it 'masks to 4 bits' do
      mbc.write_rom(0x2100, 0b1111_0011) # garde seulement 0b0011 = 3
      expect(mbc.read_rom(0x4000)).to eq(3)
    end

    it 'wraps the bank register on a smaller ROM (e.g. 64KB, 4 banks)' do
      mbc = build_mbc2(rom_bank_count: 4)
      mbc.write_rom(0x2100, 5) # au-delà de rom_bank_count -> 5 % 4 = 1
      expect(mbc.read_rom(0x4000)).to eq(1)
    end

    it 'keeps 0x0000-0x3FFF fixed on bank 0' do
      mbc.write_rom(0x2100, 5)
      expect(mbc.read_rom(0x0000)).to eq(0)
    end
  end

  describe 'RAM enable (bit 8 of the write address clear)' do
    it 'reads 0xFF when disabled' do
      expect(mbc.read_ram(0xA000)).to eq(0xFF)
    end

    it 'enables RAM access when the low nibble written is 0xA' do
      enable_ram
      mbc.write_ram(0xA000, 0x3)
      expect(mbc.read_ram(0xA000)).to eq(0xF3)
    end

    it 'ignores writes to RAM while disabled' do
      mbc.write_ram(0xA000, 0x3)
      expect(mbc.read_ram(0xA000)).to eq(0xFF)
    end

    it 'requires exactly 0xA in the low nibble, masking the rest' do
      mbc.write_rom(0x0000, 0b1111_1010) # garde seulement 0b1010 = 0xA
      mbc.write_ram(0xA000, 0x3)
      expect(mbc.read_ram(0xA000)).to eq(0xF3)
    end
  end

  describe 'RAM (512x4 bits, only the low nibble is stored)' do
    before { enable_ram }

    it 'masks written values to 4 bits, top nibble read back as 1s' do
      mbc.write_ram(0xA000, 0xFF)
      expect(mbc.read_ram(0xA000)).to eq(0xFF) # 0xF (masked) | 0xF0 (undefined top nibble)
    end

    it 'mirrors every 0x200 bytes across 0xA000-0xBFFF' do
      mbc.write_ram(0xA000, 0x5)
      expect(mbc.read_ram(0xA200)).to eq(0xF5)
      expect(mbc.read_ram(0xBE00)).to eq(0xF5)
    end
  end

  describe 'battery save' do
    it 'persists the 512-byte RAM and reloads it identically' do
      Dir.mktmpdir do |dir|
        cartridge = build_cartridge(mbc: 2, with_battery: true, rom_path: File.join(dir, 'game.gb'))
        mbc = MBC.build(cartridge)
        mbc.write_rom(0x0000, 0x0A)
        mbc.write_ram(0xA000, 0x7)

        mbc.save_battery_ram
        expect(File.size(cartridge.battery_ram_path)).to eq(512)

        reloaded = MBC.build(cartridge)
        reloaded.write_rom(0x0000, 0x0A)
        expect(reloaded.read_ram(0xA000)).to eq(0xF7)
      end
    end

    it 'does nothing without a battery' do
      cartridge = build_cartridge(mbc: 2, with_battery: false)
      expect { MBC.build(cartridge).save_battery_ram }.not_to raise_error
    end
  end
end
