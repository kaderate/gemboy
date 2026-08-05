require_relative '../lib/battery_ram'
require 'tempfile'

RSpec.describe BatteryRAM do
  describe '.load' do
    it 'returns nil when the file does not exist' do
      expect(described_class.load('/tmp/does_not_exist_battery_ram_spec.sav')).to be_nil
    end

    it 'returns the raw bytes of an existing file' do
      Tempfile.create(['battery', '.sav']) do |file|
        file.binmode
        file.write([1, 2, 3, 255].pack('C*'))
        file.flush

        expect(described_class.load(file.path)).to eq([1, 2, 3, 255])
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

        expect(described_class.load(file.path)).to eq(data)
      end
    end
  end
end
