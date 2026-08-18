require_relative '../lib/battery_ram'
require 'tempfile'

RSpec.describe BatteryRAM do
  describe '.load' do
    let(:wrong_path) { '/tmp/does_not_exist_battery_ram_spec.sav' }

    it 'returns a empty BatteryConfig when the file does not exist' do
      expect(described_class.load(wrong_path)).to eq(
        described_class::BatteryRAMConfig.new(saved_ram: nil, battery_ram_path: wrong_path)
      )
    end

    it 'treats an empty file as no saved RAM at all' do
      Tempfile.create(['battery', '.sav']) do |file|
        expect(described_class.load(file.path).saved_ram).to be_nil
      end
    end

    it 'returns a BatteryRAMConfig with the raw bytes' do
      Tempfile.create(['battery', '.sav']) do |file|
        file.binmode
        file.write([1, 2, 3, 255].pack('C*'))
        file.flush

        expect(described_class.load(file.path)).to eq(
          described_class::BatteryRAMConfig.new(saved_ram: [1, 2, 3, 255].pack('C*').bytes, battery_ram_path: file.path)
        )
      end
    end
  end

  describe '.save' do
    it 'writes the raw bytes, not their string representation' do
      Tempfile.create(['battery', '.sav']) do |file|
        described_class.save(file.path, [66, 153, 0, 0])

        expect(File.binread(file.path).bytes).to eq([66, 153, 0, 0])
      end
    end
  end

  describe 'round trip' do
    it 'returns the exact same data after save then load' do
      Tempfile.create(['battery', '.sav']) do |file|
        data = Array.new(8192) { rand(256) }

        described_class.save(file.path, data)

        expect(described_class.load(file.path).saved_ram).to eq(data)
      end
    end
  end
end
