# frozen_string_literal: true

require_relative '../../lib/mbc'

RSpec.describe MBC::MBC1 do
  ROM_BANKS = 128 # 2MB (max MBC1) : évite tout wrap via `% rom_bank_count` sur les banques hautes
  RAM_BANKS = 4 # 32KB

  subject(:mbc) { build_mbc1 }

  def build_mbc1(rom_bank_count: ROM_BANKS, ram_bank_count: RAM_BANKS)
    build_mbc(mbc: 1, rom: build_marked_rom(bank_count: rom_bank_count), ram_bank_count:)
  end

  def enable_ram = mbc.write_rom(0x0000, 0x0A)

  describe 'ROM bank select (0x2000-0x3FFF, 5 bits)' do
    it 'selects the given bank for the 0x4000-0x7FFF window' do
      mbc.write_rom(0x2000, 5)
      expect(mbc.read_rom(0x4000)).to eq(5)
    end

    it 'maps bank 0 to bank 1 (hardware quirk)' do
      mbc.write_rom(0x2000, 0)
      expect(mbc.read_rom(0x4000)).to eq(1)
    end

    it 'masks to 5 bits' do
      mbc.write_rom(0x2000, 0b1110_0011) # garde seulement 0b00011 = 3
      expect(mbc.read_rom(0x4000)).to eq(3)
    end
  end

  describe 'secondary bank register (0x4000-0x5FFF, bits 5-6)' do
    it 'extends the ROM bank for 0x4000-0x7FFF regardless of the banking mode (mode 0, default)' do
      mbc.write_rom(0x2000, 1)  # 5 bits bas = 1
      mbc.write_rom(0x4000, 1)  # registre secondaire = 1 -> bit 5

      expect(mbc.read_rom(0x4000)).to eq(0b0100001) # 33
    end

    it 'still extends the ROM bank for 0x4000-0x7FFF in mode 1' do
      mbc.write_rom(0x6000, 1) # mode 1
      mbc.write_rom(0x2000, 1)
      mbc.write_rom(0x4000, 1)

      expect(mbc.read_rom(0x4000)).to eq(0b0100001) # 33
    end

    it 'masks to 2 bits' do
      mbc.write_rom(0x2000, 1)
      mbc.write_rom(0x4000, 0b1111_1110) # garde seulement 0b10 = 2

      expect(mbc.read_rom(0x4000)).to eq(0b1000001) # 65
    end
  end

  describe 'banking mode (0x6000-0x7FFF) and the fixed 0x0000-0x3FFF window' do
    it 'keeps 0x0000-0x3FFF fixed on bank 0 in mode 0 (default), even with the secondary register set' do
      mbc.write_rom(0x4000, 1)
      expect(mbc.read_rom(0x0000)).to eq(0)
    end

    it 'applies the secondary register to 0x0000-0x3FFF in mode 1' do
      mbc.write_rom(0x6000, 1) # mode 1
      mbc.write_rom(0x4000, 1) # secondaire = 1 -> banque 32 pour la fenêtre basse

      expect(mbc.read_rom(0x0000)).to eq(32)
    end

    it 'wraps past the end of the ROM in mode 1 (512KB cartridge, banque 32 inexistante)' do
      mbc = build_mbc1(rom_bank_count: 32)
      mbc.write_rom(0x6000, 1)
      mbc.write_rom(0x4000, 1) # 1 << 5 = 32, hors ROM -> wrap sur la banque 0

      expect(mbc.read_rom(0x0000)).to eq(0)
    end

    it 'wraps modulo the ROM size, not to bank 0 (1MB cartridge)' do
      mbc = build_mbc1(rom_bank_count: 64)
      mbc.write_rom(0x6000, 1)
      mbc.write_rom(0x4000, 3) # 3 << 5 = 96, hors ROM -> 96 % 64 = 32

      expect(mbc.read_rom(0x0000)).to eq(32)
    end
  end

  describe 'external RAM banking' do
    it 'returns 0xFF when RAM is not enabled' do
      mbc.write_ram(0x0000, 0x42) # ignoré, RAM désactivée
      expect(mbc.read_ram(0x0000)).to eq(0xFF)
    end

    it 'reads/writes bank 0 by default (mode 0)' do
      enable_ram
      mbc.write_ram(0x0000, 0x42)
      expect(mbc.read_ram(0x0000)).to eq(0x42)
    end

    it 'stays on RAM bank 0 in mode 0 even if the secondary register is set' do
      enable_ram
      mbc.write_ram(0x0000, 0x11)
      mbc.write_rom(0x4000, 2) # ignoré en mode 0 pour la RAM

      expect(mbc.read_ram(0x0000)).to eq(0x11)
    end

    it 'switches RAM bank in mode 1, keeping banks independent' do
      mbc.write_rom(0x6000, 1) # mode 1
      enable_ram

      mbc.write_rom(0x4000, 0) # banque RAM 0
      mbc.write_ram(0x0000, 0xAA)

      mbc.write_rom(0x4000, 2) # banque RAM 2
      mbc.write_ram(0x0000, 0xBB)

      mbc.write_rom(0x4000, 0)
      expect(mbc.read_ram(0x0000)).to eq(0xAA) # toujours là, pas écrasé par la banque 2

      mbc.write_rom(0x4000, 2)
      expect(mbc.read_ram(0x0000)).to eq(0xBB)
    end
  end
end
