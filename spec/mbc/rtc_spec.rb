# frozen_string_literal: true

require_relative '../../lib/mbc/rtc'

RSpec.describe MBC::RTC do
  let(:t0) { 1_700_000_000 }

  def now_at(offset) = allow(Time).to receive(:now).and_return(Time.at(t0 + offset))

  def saved_config(registers, timestamp_offset)
    { rtc_registers: registers, rtc_latched_registers: registers, rtc_unix_timestamp: t0 + timestamp_offset }
  end

  describe 'restoring from a save' do
    it 'falls back on default registers when there is nothing saved' do
      now_at(0)

      expect(described_class.new(nil).rtc_data_to_save[:rtc_registers].size).to eq(5)
    end

    it 'ages the saved registers by the time elapsed since the save' do
      now_at(60 * 60)
      rtc = described_class.new(saved_config([0, 0, 0, 0, 0], 0))

      expect(rtc.rtc_data_to_save[:rtc_registers]).to eq([0, 0, 1, 0, 0])
    end

    it 'does not age a halted clock, however long it was powered off' do
      now_at(48 * 60 * 60)
      rtc = described_class.new(saved_config([0, 0, 0, 0, MBC::RTCRegisters::RTC_DH_HALT], 0))

      expect(rtc.rtc_data_to_save[:rtc_registers].first(3)).to eq([0, 0, 0])
    end
  end

  describe 'the register window' do
    subject(:rtc) { described_class.new(nil) }

    before { now_at(0) }

    it 'is not mapped until a register is selected' do
      expect(rtc.registers_mapped?).to be(false)
    end

    it 'is mapped once a register index is set, and released on -1' do
      rtc.mapped_rtc_register = 0
      expect(rtc.registers_mapped?).to be(true)

      rtc.mapped_rtc_register = -1
      expect(rtc.registers_mapped?).to be(false)
    end

    it 'reads the latched snapshot of the selected register' do
      rtc.mapped_rtc_register = 0
      rtc.write_rtc_register(42)
      rtc.latch!(0x00)
      rtc.latch!(0x01)

      expect(rtc.read_rtc_registers).to eq(42)
    end
  end

  describe '#rtc_data_to_save' do
    it 'refreshes the running registers before handing them over' do
      now_at(0)
      rtc = described_class.new(nil)
      rtc.mapped_rtc_register = 0
      rtc.write_rtc_register(0)

      now_at(30)

      expect(rtc.rtc_data_to_save[:rtc_registers].first).to eq(30)
    end
  end
end

RSpec.describe MBC::NullRTC do
  it 'answers the same protocol as a real clock' do
    expect(described_class.instance_methods(false))
      .to include(*(MBC::RTC.instance_methods(false) - Object.instance_methods))
  end

  it 'never maps the window, so the RAM always answers' do
    expect(described_class.new.registers_mapped?).to be(false)
  end

  it 'contributes nothing to the battery save' do
    expect(described_class.new.rtc_data_to_save).to eq({})
  end

  it 'swallows the writes MBC3 forwards to it' do
    null_rtc = described_class.new

    expect { null_rtc.mapped_rtc_register = 3 }.not_to raise_error
    expect { null_rtc.write_rtc_register(0x42) }.not_to raise_error
    expect { null_rtc.latch!(0x01) }.not_to raise_error
  end
end
