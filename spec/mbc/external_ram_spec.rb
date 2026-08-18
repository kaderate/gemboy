# frozen_string_literal: true

require 'tmpdir'
require_relative '../../lib/mbc/external_ram'

RSpec.describe MBC::ExternalRAM do
  describe 'enable gate' do
    it 'returns 0xFF while disabled' do
      ram = build_external_ram(enabled: false)
      expect(ram.read(0x0000)).to eq(0xFF)
    end

    it 'ignores writes while disabled' do
      ram = build_external_ram(enabled: false)
      ram.write(0x0000, 0x42)
      ram.enabled = true

      expect(ram.read(0x0000)).to eq(0x00)
    end
  end

  describe 'banking' do
    subject(:ram) { build_external_ram(bank_count: 4) }

    it 'keeps banks independent' do
      ram.write(0x0000, 0xAA)
      ram.bank = 2
      ram.write(0x0000, 0xBB)

      ram.bank = 0
      expect(ram.read(0x0000)).to eq(0xAA)

      ram.bank = 2
      expect(ram.read(0x0000)).to eq(0xBB)
    end

    it 'wraps modulo the declared bank count' do
      ram.write(0x0000, 0xAA)
      ram.bank = 4

      expect(ram.read(0x0000)).to eq(0xAA)
    end
  end

  describe 'cartridge without RAM' do
    subject(:ram) { build_external_ram(bank_count: 0) }

    it 'reads 0xFF' do
      expect(ram.read(0x0000)).to eq(0xFF)
    end

    it 'silently drops writes instead of growing the backing array' do
      ram.write(0x0000, 0x42)

      expect(ram.bytes).to be_empty
      expect(ram.read(0x0000)).to eq(0xFF)
    end
  end

  describe 'battery backup' do
    around do |example|
      Dir.mktmpdir do |dir|
        @battery_path = File.join(dir, 'game.sav')
        example.run
      end
    end

    it 'saves on the disable edge' do
      ram = build_external_ram(battery_path: @battery_path)
      ram.write(0x0000, 0x42)
      ram.enabled = false

      expect(File.binread(@battery_path).bytes.first).to eq(0x42)
    end

    it 'does not save while the RAM stays enabled' do
      ram = build_external_ram(battery_path: @battery_path)
      ram.write(0x0000, 0x42)

      expect(File.exist?(@battery_path)).to be(false)
    end

    it 'reloads the saved content on the next boot' do
      ram = build_external_ram(battery_path: @battery_path)
      ram.write(0x0000, 0x42)
      ram.save!

      reloaded = build_external_ram(battery_path: @battery_path)
      expect(reloaded.read(0x0000)).to eq(0x42)
    end

    it 'allocates a full-sized RAM when the save file exists but is empty' do
      File.binwrite(@battery_path, '')
      ram = build_external_ram(bank_count: 2, battery_path: @battery_path)

      expect(ram.bytes.size).to eq(2 * described_class::BANK_SIZE)
      ram.write(0x0000, 0x42)
      expect(ram.read(0x0000)).to eq(0x42)
    end

    it 'does nothing on save! without a battery' do
      ram = build_external_ram(battery_path: nil)
      ram.write(0x0000, 0x42)

      expect { ram.save! }.not_to raise_error
    end
  end
end
