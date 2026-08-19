require_relative '../lib/battery_ram'
require 'tempfile'

RSpec.describe BatteryRAM do
  BANK_SIZE = MBC::Constants::RAM_BANK_SIZE
  RTC = [1, 2, 3, 4, 5].freeze
  LATCHED_RTC = [10, 20, 30, 40, 50].freeze

  def ram_bytes(bank_count = 1) = Array.new(bank_count * BANK_SIZE) { rand(256) }

  def write_sav(file, ram, trailer = '')
    file.binmode
    file.write(ram.pack('C*') + trailer)
    file.flush
  end

  describe '.load' do
    it 'returns an empty config when the file does not exist' do
      path = '/tmp/does_not_exist_battery_ram_spec.sav'

      expect(described_class.load(path, bank_count: 1)).to eq(
        described_class::BatteryRAMConfig.new(saved_ram: nil, battery_ram_path: path)
      )
    end

    it 'treats an empty file as no saved RAM at all' do
      Tempfile.create(['battery', '.sav']) do |file|
        expect(described_class.load(file.path, bank_count: 1).saved_ram).to be_nil
      end
    end

    it 'reads a RAM-only save, without any RTC data' do
      Tempfile.create(['battery', '.sav']) do |file|
        ram = ram_bytes
        write_sav(file, ram)

        config = described_class.load(file.path, bank_count: 1)
        expect(config.saved_ram).to eq(ram)
        expect(config.rtc_config).to eq(rtc_registers: nil, rtc_latched_registers: nil, rtc_unix_timestamp: nil)
      end
    end

    it 'splits RAM from the RTC trailer over several banks' do
      Tempfile.create(['battery', '.sav']) do |file|
        ram = ram_bytes(4)
        write_sav(file, ram, RTC.pack('V5') + LATCHED_RTC.pack('V5') + [1_700_000_000].pack('Q<'))

        config = described_class.load(file.path, bank_count: 4)
        expect(config.saved_ram).to eq(ram)
        expect(config.rtc_registers).to eq(RTC)
        expect(config.rtc_latched_registers).to eq(LATCHED_RTC)
        expect(config.rtc_unix_timestamp).to eq(1_700_000_000)
      end
    end

    it 'accepts the legacy 32-bit timestamp variant (44-byte trailer)' do
      Tempfile.create(['battery', '.sav']) do |file|
        write_sav(file, ram_bytes, RTC.pack('V5') + LATCHED_RTC.pack('V5') + [1_700_000_000].pack('V'))

        expect(described_class.load(file.path, bank_count: 1).rtc_unix_timestamp).to eq(1_700_000_000)
      end
    end

    it 'warns and keeps the game data when the trailer has an unknown size' do
      Tempfile.create(['battery', '.sav']) do |file|
        ram = ram_bytes
        write_sav(file, ram, 'garbage')

        config = nil
        expect { config = described_class.load(file.path, bank_count: 1) }
          .to output(/Ignoring 7 unexpected trailing bytes/).to_stderr
        expect(config.saved_ram).to eq(ram)
        expect(config.rtc_registers).to be_nil
      end
    end

    it 'leaves the file untouched when it warns, so the corruption stays diagnosable' do
      Tempfile.create(['battery', '.sav']) do |file|
        write_sav(file, ram_bytes, 'garbage')
        before = File.binread(file.path)

        expect { described_class.load(file.path, bank_count: 1) }.to output.to_stderr

        expect(File.binread(file.path)).to eq(before)
      end
    end

    it 'refuses a file shorter than the declared RAM, rather than showing the game an empty save' do
      Tempfile.create(['battery', '.sav']) do |file|
        write_sav(file, ram_bytes.first(BANK_SIZE - 10))

        expect { described_class.load(file.path, bank_count: 1) }
          .to raise_error(described_class::CorruptedBatteryRAMError, /Truncated.+expected at least 8192 bytes, got 8182/m)
      end
    end

    it 'names the offending path when it refuses a truncated file' do
      Tempfile.create(['battery', '.sav']) do |file|
        write_sav(file, ram_bytes.first(10))

        expect { described_class.load(file.path, bank_count: 1) }
          .to raise_error(described_class::CorruptedBatteryRAMError, /#{Regexp.escape(file.path)}/)
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

    it 'appends a 48-byte trailer when RTC data is given' do
      Tempfile.create(['battery', '.sav']) do |file|
        ram = ram_bytes
        described_class.save(file.path, ram, rtc_registers: RTC, rtc_latched_registers: LATCHED_RTC)

        expect(File.binread(file.path).bytesize).to eq(ram.size + 48)
      end
    end

    it 'does not mutate the RAM it is given' do
      Tempfile.create(['battery', '.sav']) do |file|
        ram = ram_bytes
        described_class.save(file.path, ram, rtc_registers: RTC, rtc_latched_registers: LATCHED_RTC)

        expect(ram.size).to eq(BANK_SIZE)
      end
    end

    it 'refuses a half-filled RTC trailer' do
      Tempfile.create(['battery', '.sav']) do |file|
        expect { described_class.save(file.path, ram_bytes, rtc_registers: RTC) }
          .to raise_error(ArgumentError)
      end
    end
  end

  describe 'round trip' do
    it 'returns the exact same data after save then load' do
      Tempfile.create(['battery', '.sav']) do |file|
        ram = ram_bytes

        described_class.save(file.path, ram)

        expect(described_class.load(file.path, bank_count: 1).saved_ram).to eq(ram)
      end
    end

    it 'returns the same RAM and RTC data after save then load' do
      Tempfile.create(['battery', '.sav']) do |file|
        ram = ram_bytes(2)

        described_class.save(file.path, ram, rtc_registers: RTC, rtc_latched_registers: LATCHED_RTC)
        config = described_class.load(file.path, bank_count: 2)

        expect(config.saved_ram).to eq(ram)
        expect(config.rtc_registers).to eq(RTC)
        expect(config.rtc_latched_registers).to eq(LATCHED_RTC)
        expect(config.rtc_unix_timestamp).to be_within(2).of(Time.now.to_i)
      end
    end
  end
end
