# frozen_string_literal: true

require_relative '../../lib/mbc'

RSpec.describe MBC::RTCRegisters do
  DAY = 24 * 60 * 60
  HALT_BIT = 0x40
  CARRY_BIT = 0x80

  def registers(s: 0, m: 0, h: 0, dl: 0, dh: 0) = described_class.new(s, m, h, dl, dh)
  def day_of(rtc) = ((rtc.rtc_dh & 0x01) << 8) | rtc.rtc_dl
  def carry?(rtc) = rtc.rtc_dh.anybits?(CARRY_BIT)

  describe '#advance' do
    it 'rolls seconds into minutes' do
      rtc = registers(s: 59)
      rtc.advance(1)

      expect([rtc.rtc_s, rtc.rtc_m]).to eq([0, 1])
    end

    it 'rolls minutes into hours' do
      rtc = registers(s: 59, m: 59)
      rtc.advance(1)

      expect([rtc.rtc_s, rtc.rtc_m, rtc.rtc_h]).to eq([0, 0, 1])
    end

    it 'rolls hours into days' do
      rtc = registers(s: 59, m: 59, h: 23)
      rtc.advance(1)

      expect([rtc.rtc_h, rtc.rtc_dl]).to eq([0, 1])
    end

    it 'spreads a large delta over every register' do
      rtc = registers
      rtc.advance((2 * DAY) + (3 * 60 * 60) + (4 * 60) + 5)

      expect(rtc.to_a).to eq([5, 4, 3, 2, 0])
    end

    it 'starts from the current register values, not from zero' do
      rtc = registers(s: 30, m: 10, h: 5)
      rtc.advance(60)

      expect(rtc.to_a.first(3)).to eq([30, 11, 5])
    end

    it 'ignores a zero delta' do
      rtc = registers(s: 42)

      expect { rtc.advance(0) }.not_to(change { rtc.to_a })
    end

    it 'ignores a negative delta, as when the host clock is stepped backwards' do
      rtc = registers(s: 42)

      expect { rtc.advance(-100) }.not_to(change { rtc.to_a })
    end

    it 'preserves the halt bit' do
      rtc = registers(dh: HALT_BIT)
      rtc.advance(60)

      expect(rtc.rtc_dh & HALT_BIT).to eq(HALT_BIT)
    end
  end

  describe 'the 9-bit day counter' do
    it 'keeps the 9th bit in DH bit 0' do
      rtc = registers
      rtc.advance(300 * DAY)

      expect(day_of(rtc)).to eq(300)
      expect(rtc.rtc_dl).to eq(44) # 300 - 256
    end

    it 'does not raise the carry below the overflow, even past 255 days' do
      rtc = registers(dl: 300 % 256, dh: 0x01) # jour 300
      rtc.advance(DAY)

      expect(day_of(rtc)).to eq(301)
      expect(carry?(rtc)).to be(false)
    end

    it 'raises the carry and wraps to day 0 when passing 511 days' do
      rtc = registers(dl: 511 % 256, dh: 0x01) # jour 511
      rtc.advance(DAY)

      expect(day_of(rtc)).to eq(0)
      expect(carry?(rtc)).to be(true)
    end

    it 'raises the carry when a single advance jumps over the whole counter' do
      rtc = registers
      rtc.advance(512 * DAY)

      expect(carry?(rtc)).to be(true)
    end

    it 'keeps the carry set on later advances, until software clears it' do
      rtc = registers(dl: 511 % 256, dh: 0x01)
      rtc.advance(DAY)
      rtc.advance(DAY)

      expect(day_of(rtc)).to eq(1)
      expect(carry?(rtc)).to be(true)

      rtc.set_register(4, 0x00) # le jeu efface DH
      rtc.advance(DAY)

      expect(carry?(rtc)).to be(false)
    end
  end

  describe '#set_register' do
    it 'masks each register to its physical width' do
      rtc = registers
      5.times { rtc.set_register(_1, 0xFF) }

      expect(rtc.to_a).to eq([0x3F, 0x3F, 0x1F, 0xFF, 0xC1])
    end

    it 'stores an out-of-range value instead of clamping it' do
      rtc = registers
      rtc.set_register(0, 62) # au-delà de 59, mais dans les 6 bits du compteur

      expect(rtc.rtc_s).to eq(62)
    end
  end

  describe '#to_a' do
    it 'returns the five registers in RTC order' do
      expect(registers(s: 1, m: 2, h: 3, dl: 4, dh: 5).to_a).to eq([1, 2, 3, 4, 5])
    end
  end
end
