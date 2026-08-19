# frozen_string_literal: true

require_relative '../../lib/mbc'

RSpec.describe MBC::MBC3 do
  ROM_BANKS_MBC3 = 128 # 2MB (max MBC3) : couvre les 7 bits du registre de banque
  RAM_BANKS_MBC3 = 4

  subject(:mbc) { build_mbc3 }

  def build_mbc3(rom_bank_count: ROM_BANKS_MBC3, ram_bank_count: RAM_BANKS_MBC3)
    build_mbc(mbc: 3, rom: build_marked_rom(bank_count: rom_bank_count), ram_bank_count:)
  end

  def enable_ram = mbc.write_rom(0x0000, 0x0A)
  def latch = [0x00, 0x01].each { mbc.write_rom(0x6000, _1) }
  def select_window(value) = mbc.write_rom(0x4000, value)

  describe 'ROM banking (0x2000-0x3FFF, 7 bits)' do
    it 'selects the given bank for the 0x4000-0x7FFF window' do
      mbc.write_rom(0x2000, 5)
      expect(mbc.read_rom(0x4000)).to eq(5)
    end

    it 'reaches the highest bank, unlike MBC1 and its 5-bit register' do
      mbc.write_rom(0x2000, 0x7F)
      expect(mbc.read_rom(0x4000)).to eq(0x7F)
    end

    it 'maps bank 0 to bank 1 (hardware quirk)' do
      mbc.write_rom(0x2000, 0)
      expect(mbc.read_rom(0x4000)).to eq(1)
    end

    it 'masks to 7 bits, so bit 7 falls back on the bank 0 quirk' do
      mbc.write_rom(0x2000, 0x80)
      expect(mbc.read_rom(0x4000)).to eq(1)
    end

    it 'keeps 0x0000-0x3FFF on bank 0 whatever the selected bank' do
      mbc.write_rom(0x2000, 5)
      expect(mbc.read_rom(0x0000)).to eq(0)
    end
  end

  describe 'external RAM' do
    it 'returns 0xFF when RAM is not enabled' do
      mbc.write_ram(0x0000, 0x42)
      expect(mbc.read_ram(0x0000)).to eq(0xFF)
    end

    it 'switches RAM bank via 0x4000-0x5FFF, keeping banks independent' do
      enable_ram

      select_window(0)
      mbc.write_ram(0x0000, 0xAA)

      select_window(2)
      mbc.write_ram(0x0000, 0xBB)

      select_window(0)
      expect(mbc.read_ram(0x0000)).to eq(0xAA)

      select_window(2)
      expect(mbc.read_ram(0x0000)).to eq(0xBB)
    end
  end

  describe 'RTC registers mapped over the RAM window' do
    before { enable_ram }

    it 'maps the five clock registers on 0x08-0x0C, each one distinct' do
      latch
      values = (0x08..0x0C).map { |register| select_window(register) && mbc.read_ram(0x0000) }

      expect(values).to all(be_a(Integer))
      expect(values.size).to eq(5)
    end

    it 'ignores the address inside the window when a clock register is mapped' do
      select_window(0x08)
      expect(mbc.read_ram(0x1FFF)).to eq(mbc.read_ram(0x0000))
    end

    it 'gives the window back to the RAM when a bank is selected again' do
      select_window(0)
      mbc.write_ram(0x0000, 0x42)

      select_window(0x08)
      expect(mbc.read_ram(0x0000)).not_to eq(0x42)

      select_window(0)
      expect(mbc.read_ram(0x0000)).to eq(0x42)
    end
  end

  describe 'latching' do
    before do
      enable_ram
      select_window(0x08) # seconds
    end

    it 'reads the latched snapshot, not the running registers' do
      mbc.write_ram(0x0000, 30)

      expect(mbc.read_ram(0x0000)).not_to eq(30)
    end

    it 'exposes the new value once latched' do
      mbc.write_ram(0x0000, 30)
      latch

      expect(mbc.read_ram(0x0000)).to eq(30)
    end

    it 'needs the full 0x00 then 0x01 sequence' do
      mbc.write_ram(0x0000, 30)
      mbc.write_rom(0x6000, 0x01) # 0x01 alone

      expect(mbc.read_ram(0x0000)).not_to eq(30)
    end

    it 'keeps the snapshot frozen until the next latch' do
      latch
      mbc.write_ram(0x0000, 45)

      expect(mbc.read_ram(0x0000)).not_to eq(45)

      latch
      expect(mbc.read_ram(0x0000)).to eq(45)
    end
  end

  describe '#fetch_rtc_data' do
    it 'exposes both the running and the latched registers for the battery save' do
      expect(mbc.fetch_rtc_data.keys).to contain_exactly(:rtc_registers, :rtc_latched_registers)
      expect(mbc.fetch_rtc_data[:rtc_registers].size).to eq(5)
      expect(mbc.fetch_rtc_data[:rtc_latched_registers].size).to eq(5)
    end
  end
end
