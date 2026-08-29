# frozen_string_literal: true

require_relative '../lib/interrupts'

RSpec.describe Interrupts do
  subject(:interrupts) { described_class.new }

  describe 'initial state' do
    it 'starts with IME disabled and IE/IF cleared' do
      expect(interrupts.ime).to eq(false)
      expect(interrupts.read(0xFFFF)).to eq(0)
      expect(interrupts.read(0xFF0F)).to eq(0)
    end
  end

  describe '#read/#write' do
    it 'reads/writes IF (0xFF0F)' do
      interrupts.write(0xFF0F, 0x1F)
      expect(interrupts.read(0xFF0F)).to eq(0x1F)
    end

    it 'reads/writes IE (0xFFFF), independently from IF' do
      interrupts.write(0xFFFF, 0x1F)
      expect(interrupts.read(0xFFFF)).to eq(0x1F)
      expect(interrupts.read(0xFF0F)).to eq(0)
    end
  end

  describe '#request/#clear_requested (IF)' do
    it 'sets the bit for the given interrupt' do
      interrupts.request(:vblank)
      expect(interrupts.read(0xFF0F)).to eq(0x01)
    end

    it 'sets the bit at the right position for each interrupt' do
      interrupts.request(:lcd_stat)
      interrupts.request(:timer)
      interrupts.request(:serial)
      interrupts.request(:joypad)
      expect(interrupts.read(0xFF0F)).to eq(0b0001_1110)
    end

    it 'does not affect other pending requests' do
      interrupts.request(:vblank)
      interrupts.request(:timer)
      interrupts.clear_requested(:vblank)
      expect(interrupts.read(0xFF0F)).to eq(0b0000_0100)
    end

    it 'raises on an unknown interrupt name' do
      expect { interrupts.request(:bogus) }.to raise_error(RuntimeError, /Unknown interrupt name/)
    end
  end

  describe '#enable/#disable (IE)' do
    it 'sets the bit for the given interrupt' do
      interrupts.enable(:joypad)
      expect(interrupts.read(0xFFFF)).to eq(0b0001_0000)
    end

    it 'does not affect other enabled interrupts' do
      interrupts.enable(:vblank)
      interrupts.enable(:timer)
      interrupts.disable(:vblank)
      expect(interrupts.read(0xFFFF)).to eq(0b0000_0100)
    end

    it 'raises on an unknown interrupt name' do
      expect { interrupts.enable(:bogus) }.to raise_error(RuntimeError, /Unknown interrupt name/)
    end
  end

  describe '#enabled?' do
    it 'reflects the IE mask for a given interrupt' do
      expect(interrupts.enabled?(:serial)).to eq(false)
      interrupts.enable(:serial)
      expect(interrupts.enabled?(:serial)).to eq(true)
    end
  end

  describe '#pending?' do
    it 'is false when nothing is requested or enabled' do
      expect(interrupts.pending?).to eq(false)
    end

    it 'is false when requested but not enabled' do
      interrupts.request(:vblank)
      expect(interrupts.pending?).to eq(false)
    end

    it 'is false when enabled but not requested' do
      interrupts.enable(:vblank)
      expect(interrupts.pending?).to eq(false)
    end

    it 'is true when both enabled and requested' do
      interrupts.enable(:vblank)
      interrupts.request(:vblank)
      expect(interrupts.pending?).to eq(true)
    end
  end

  describe '#any_requested?' do
    it 'ignores IE, unlike #pending?' do
      interrupts.request(:vblank) # not enabled in IE
      expect(interrupts.any_requested?).to eq(true)
      expect(interrupts.pending?).to eq(false)
    end

    it 'is false when nothing is requested' do
      expect(interrupts.any_requested?).to eq(false)
    end
  end

  describe '#most_important' do
    it 'is nil when IME is disabled, even if an interrupt is pending' do
      interrupts.enable(:vblank)
      interrupts.request(:vblank)
      expect(interrupts.most_important).to be_nil
    end

    it 'is nil when nothing is both enabled and requested' do
      interrupts.ime = true
      interrupts.request(:vblank) # not enabled
      expect(interrupts.most_important).to be_nil
    end

    it 'returns the sole pending interrupt' do
      interrupts.ime = true
      interrupts.enable(:timer)
      interrupts.request(:timer)
      expect(interrupts.most_important).to eq(:timer)
    end

    it 'picks the highest-priority (lowest vector) interrupt when several are pending' do
      interrupts.ime = true
      %i[vblank lcd_stat timer serial joypad].each { interrupts.enable(_1) }
      interrupts.request(:joypad)
      interrupts.request(:timer)
      interrupts.request(:lcd_stat)
      expect(interrupts.most_important).to eq(:lcd_stat)
    end
  end

  describe '#vector' do
    it 'maps each interrupt to its handler address' do
      expect(interrupts.vector(:vblank)).to eq(0x40)
      expect(interrupts.vector(:lcd_stat)).to eq(0x48)
      expect(interrupts.vector(:timer)).to eq(0x50)
      expect(interrupts.vector(:serial)).to eq(0x58)
      expect(interrupts.vector(:joypad)).to eq(0x60)
    end
  end

  describe '#requested_mask/#enabled_mask' do
    it 'decodes IF into a per-interrupt boolean hash' do
      interrupts.request(:timer)
      expect(interrupts.requested_mask).to eq(vblank: false, lcd_stat: false, timer: true, serial: false, joypad: false)
    end

    it 'decodes IE into a per-interrupt boolean hash' do
      interrupts.enable(:serial)
      expect(interrupts.enabled_mask).to eq(vblank: false, lcd_stat: false, timer: false, serial: true, joypad: false)
    end
  end
end
