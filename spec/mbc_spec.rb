# frozen_string_literal: true

require_relative '../lib/mbc'

RSpec.describe MBC do
  describe '.build' do
    it 'returns a NullMBC for a cartridge without any controller' do
      expect(described_class.build(build_cartridge(mbc: 0))).to be_a(MBC::NullMBC)
    end

    it 'returns an MBC1' do
      expect(described_class.build(build_cartridge(mbc: 1))).to be_a(MBC::MBC1)
    end

    it 'returns an MBC5' do
      expect(described_class.build(build_cartridge(mbc: 5))).to be_a(MBC::MBC5)
    end

    it 'raises for a controller declared in the header but not implemented' do
      expect { described_class.build(build_cartridge(mbc: 3)) }
        .to raise_error(MBC::UnsupportedMBC, /3/)
    end
  end
end
