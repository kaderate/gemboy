# frozen_string_literal: true

require 'tempfile'
require_relative '../lib/cartridge_loader'

RSpec.describe CartridgeLoader do
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
    # Minimal 32KB ROM: only the cartridge type byte matters, the rest can stay zeroed
    # (ROM size 0x00 = 32KB, RAM size 0x00 = none).
    def with_rom(cart_type_byte)
      rom = Array.new(0x8000, 0x00)
      rom[0x0147] = cart_type_byte

      Tempfile.create(['fake', '.gb']) do |file|
        file.binmode
        file.write(rom.pack('C*'))
        file.flush
        yield file.path
      end
    end

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
end
