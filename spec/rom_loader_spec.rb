# frozen_string_literal: true

require 'tempfile'
require_relative '../lib/rom_loader'

RSpec.describe RomLoader do
  describe 'missing ROM file' do
    it 'raises ROMNotFound rather than a generic error' do
      expect { described_class.new('/tmp/definitely-missing.gb') }.to raise_error(RomLoader::ROMNotFound)
    end

    it 'names the offending path in the message' do
      expect { described_class.new('/tmp/definitely-missing.gb') }
        .to raise_error(RomLoader::ROMNotFound, %r{/tmp/definitely-missing\.gb})
    end

    it 'is a StandardError, so a bare rescue in the CLI catches it' do
      expect(RomLoader::ROMNotFound.ancestors).to include(StandardError)
    end
  end
end
