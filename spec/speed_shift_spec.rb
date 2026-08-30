require_relative '../lib/speed_shift'

RSpec.describe SpeedShift do
  subject(:speed_shift) { described_class.new }

  describe '#initialize' do
    it 'starts unarmed, at single speed' do
      expect(speed_shift.armed).to eq(false)
      expect(speed_shift.double_speed).to eq(false)
    end
  end

  describe '#arm!' do
    it 'arms when the written value has bit 0 set' do
      speed_shift.arm!(0x01)
      expect(speed_shift.armed).to eq(true)
    end

    it 'does not arm when bit 0 is clear, even if other bits are set' do
      speed_shift.arm!(0x80)
      expect(speed_shift.armed).to eq(false)
    end

    it 'disarms when bit 0 is clear' do
      speed_shift.arm!(0x01)
      speed_shift.arm!(0x00)
      expect(speed_shift.armed).to eq(false)
    end
  end

  describe '#switch_speed!' do
    it 'does nothing when not armed' do
      speed_shift.switch_speed!
      expect(speed_shift.double_speed).to eq(false)
    end

    it 'toggles double_speed and disarms when armed' do
      speed_shift.arm!(0x01)
      speed_shift.switch_speed!
      expect(speed_shift.double_speed).to eq(true)
      expect(speed_shift.armed).to eq(false)
    end

    it 'toggles back to single speed on a second armed switch' do
      speed_shift.arm!(0x01)
      speed_shift.switch_speed!
      speed_shift.arm!(0x01)
      speed_shift.switch_speed!
      expect(speed_shift.double_speed).to eq(false)
    end
  end

  describe '#shift' do
    it 'is 0 at single speed' do
      expect(speed_shift.shift).to eq(0)
    end

    it 'is 1 at double speed' do
      speed_shift.arm!(0x01)
      speed_shift.switch_speed!
      expect(speed_shift.shift).to eq(1)
    end
  end

  describe '#key1_register' do
    it 'is 0x00 at single speed, unarmed' do
      expect(speed_shift.key1_register).to eq(0x00)
    end

    it 'sets bit 0 when armed' do
      speed_shift.arm!(0x01)
      expect(speed_shift.key1_register).to eq(0x01)
    end

    it 'sets bit 7 at double speed' do
      speed_shift.arm!(0x01)
      speed_shift.switch_speed!
      expect(speed_shift.key1_register).to eq(0x80)
    end
  end
end
