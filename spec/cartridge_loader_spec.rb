# frozen_string_literal: true

require 'tempfile'
require_relative '../lib/cartridge_loader'

RSpec.describe CartridgeLoader do
  # Minimal 32KB ROM: only the bytes under test matter, the rest can stay zeroed
  # (ROM size 0x00 = 32KB, RAM size 0x00 = none).
  def with_rom(cart_type_byte, cgb_flag: 0x00, title: nil)
    rom = Array.new(0x8000, 0x00)
    rom[0x0147] = cart_type_byte
    rom[0x0143] = cgb_flag
    title&.each_byte&.with_index { |byte, i| rom[0x0134 + i] = byte }

    Tempfile.create(['fake', '.gb']) do |file|
      file.binmode
      file.write(rom.pack('C*'))
      file.flush
      yield file.path
    end
  end

  describe 'missing ROM file' do
    it 'raises ROMNotFound rather than a generic error' do
      expect { described_class.new('/tmp/definitely-missing.gb') }.to raise_error(CartridgeLoader::ROMNotFound)
    end

    it 'names the offending path in the message' do
      expect { described_class.new('/tmp/definitely-missing.gb') }
        .to raise_error(CartridgeLoader::ROMNotFound, %r{/tmp/definitely-missing\.gb})
    end

    it 'is a StandardError, so a bare rescue in the CLI catches it' do
      expect(CartridgeLoader::ROMNotFound.ancestors).to include(StandardError)
    end
  end

  describe 'unsupported cartridge type' do
    it 'raises UnsupportedCartridgeType rather than a NoMethodError on nil' do
      with_rom(0xFF) do |path| # Invalid cartridge type
        expect { described_class.new(path) }.to raise_error(CartridgeLoader::UnsupportedCartridgeType)
      end
    end

    it 'names the offending byte in the message' do
      with_rom(0x1C) do |path| # MBC5+RUMBLE
        expect { described_class.new(path) }.to raise_error(CartridgeLoader::UnsupportedCartridgeType, /0x1C/)
      end
    end

    it 'names the offending path in the message' do
      with_rom(0xFF) do |path|
        expect { described_class.new(path) }.to raise_error(CartridgeLoader::UnsupportedCartridgeType, /#{Regexp.escape(path)}/)
      end
    end

    it 'is a StandardError, so a bare rescue in the CLI catches it' do
      expect(CartridgeLoader::UnsupportedCartridgeType.ancestors).to include(StandardError)
    end

    it 'accepts a supported type without raising' do
      with_rom(0x00) do |path| # ROM only
        expect { described_class.new(path) }.not_to raise_error
      end
    end
  end

  describe 'CGB flag (0x0143)' do
    it 'reports :only for a CGB-exclusive cartridge' do
      with_rom(0x00, cgb_flag: 0xC0) do |path|
        expect(described_class.new(path).cgb).to eq(:only)
      end
    end

    it 'reports :enhanced for a CGB cartridge that still runs on DMG' do
      with_rom(0x00, cgb_flag: 0x80) do |path|
        expect(described_class.new(path).cgb).to eq(:enhanced)
      end
    end

    it 'reports :none for a plain DMG cartridge' do
      with_rom(0x00, cgb_flag: 0x00) do |path|
        expect(described_class.new(path).cgb).to eq(:none)
      end
    end

    it 'reports :none for an unknown value in the flag byte' do
      with_rom(0x00, cgb_flag: 0x42) do |path|
        expect(described_class.new(path).cgb).to eq(:none)
      end
    end

    it 'is carried by the cartridge config, alongside with_battery' do
      with_rom(0x00, cgb_flag: 0xC0) do |path|
        expect(described_class.new(path).cartridge.cartridge_config.cgb).to eq(:only)
      end
    end
  end

  describe 'title' do
    it 'stops before the manufacturer code and the CGB flag on a CGB cartridge' do
      with_rom(0x00, cgb_flag: 0xC0, title: 'PM_CRYSTAL') do |path|
        expect(described_class.new(path).name.delete("\x00")).to eq('PM_CRYSTAL')
      end
    end

    it 'does not leak the CGB flag byte into the name' do
      with_rom(0x00, cgb_flag: 0x80, title: 'POKEMON_GLDAAUF') do |path|
        expect(described_class.new(path).name).not_to include("\x80".b)
      end
    end

    it 'still spans the full 16 bytes on a DMG cartridge' do
      with_rom(0x00, title: 'TETRIS') do |path|
        expect(described_class.new(path).name).to eq("TETRIS#{"\x00" * 10}")
      end
    end
  end
end
