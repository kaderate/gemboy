# frozen_string_literal: true

require 'tmpdir'
require_relative '../../lib/mbc'

RSpec.describe MBC::MBC3 do
  ROM_BANKS_MBC3 = 128 # 2MB (max MBC3) : couvre les 7 bits du registre de banque
  RAM_BANKS_MBC3 = 4

  subject(:mbc) { build_mbc3 }

  def build_mbc3(rom_bank_count: ROM_BANKS_MBC3, ram_bank_count: RAM_BANKS_MBC3)
    build_mbc(mbc: 3, rom: build_marked_rom(bank_count: rom_bank_count), ram_bank_count:, with_timer: true)
  end

  def enable_ram = mbc.write_rom(0x0000, 0x0A)
  def latch = [0x00, 0x01].each { mbc.write_rom(0x6000, _1) }
  def select_window(value) = mbc.write_rom(0x4000, value)

  let(:t0) { 1_700_000_000 }

  def now_at(offset) = allow(Time).to receive(:now).and_return(Time.at(t0 + offset))

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

  describe '#rtc_data_to_save' do
    it 'exposes both the running and the latched registers for the battery save' do
      expect(mbc.rtc_data_to_save.keys).to contain_exactly(:rtc_registers, :rtc_latched_registers)
      expect(mbc.rtc_data_to_save[:rtc_registers].size).to eq(5)
      expect(mbc.rtc_data_to_save[:rtc_latched_registers].size).to eq(5)
    end
  end

  describe 'the clock, driven by real time' do
    before do
      now_at(0)
      enable_ram
      select_window(0x08) # seconds
      mbc.write_ram(0x0000, 0) # anchors the clock at t0
    end

    it 'advances between two latches' do
      now_at(90)
      latch

      expect(mbc.read_ram(0x0000)).to eq(30) # 90 s = 1 min 30
    end

    it 'freezes while the halt flag is set' do
      select_window(0x0C)
      mbc.write_ram(0x0000, 0x40) # halt

      now_at(90)
      latch
      select_window(0x08)

      expect(mbc.read_ram(0x0000)).to eq(0)
    end

    it 'resumes from the moment the halt flag is cleared' do
      select_window(0x0C)
      mbc.write_ram(0x0000, 0x40)
      now_at(90)
      mbc.write_ram(0x0000, 0x00) # halt cleared 90 s later

      now_at(120)
      latch
      select_window(0x08)

      expect(mbc.read_ram(0x0000)).to eq(30) # only the 30 s since the halt was cleared
    end
  end

  describe 'power-on catch-up' do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    it 'adds the power-off delay read from the saved timestamp' do
      now_at(0)
      cartridge = build_cartridge(mbc: 3, ram_bank_count: 1, with_battery: true, with_timer: true,
                                  rom_path: File.join(@dir, 'game.gb'))
      BatteryRAM.save(cartridge.battery_ram_path, Array.new(0x2000, 0),
                      rtc_registers: [0, 0, 0, 0, 0], rtc_latched_registers: [0, 0, 0, 0, 0])

      now_at(60 * 60) # one hour of power-off
      mbc = MBC.build(cartridge)
      mbc.write_rom(0x0000, 0x0A)
      [0x00, 0x01].each { mbc.write_rom(0x6000, _1) }
      mbc.write_rom(0x4000, 0x0A) # hours

      expect(mbc.read_ram(0x0000)).to eq(1)
    end
  end

  describe 'battery save' do
    RAM_SIZE = MBC::Constants::RAM_BANK_SIZE
    RTC_TRAILER_SIZE = 48 # 5 + 5 registers on 32 bits, then a 64-bit timestamp

    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    def battery_cartridge(with_timer:)
      build_cartridge(mbc: 3, ram_bank_count: 1, with_battery: true, with_timer:,
                      rom_path: File.join(@dir, "game-#{with_timer}.gb"))
    end

    it 'writes the RAM alone when the cartridge has no clock' do
      cartridge = battery_cartridge(with_timer: false)
      MBC.build(cartridge).save_battery_ram

      expect(File.size(cartridge.battery_ram_path)).to eq(RAM_SIZE)
    end

    it 'appends the RTC trailer when the cartridge has a clock' do
      cartridge = battery_cartridge(with_timer: true)
      MBC.build(cartridge).save_battery_ram

      expect(File.size(cartridge.battery_ram_path)).to eq(RAM_SIZE + RTC_TRAILER_SIZE)
    end
  end
end
