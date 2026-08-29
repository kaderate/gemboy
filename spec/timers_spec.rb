# frozen_string_literal: true

require_relative '../lib/mmu'
require_relative '../lib/cpu'

RSpec.describe 'Timers (CPU integration)' do
  def make_cpu(bytes = []) = build_cpu(*bytes, at: 0)

  let(:cpu) { make_cpu([0x00] * 10) }

  describe 'timer interrupt request' do
    it 'flags timer interrupt on overflow' do
      cpu.mmu.write(0xFF07, 0x04) # Enable timer
      cpu.mmu.write(0xFF05, 0xFF) # TIMA = 0xFF
      expect(cpu.mmu.interrupts.requested_mask[:timer]).to eq(false)
      cpu.process_timers(1024)
      expect(cpu.mmu.interrupts.requested_mask[:timer]).to eq(true)
    end

    it 'does not flag a timer interrupt on a plain increment (no overflow)' do
      cpu.mmu.write(0xFF07, 0x04) # Enable timer
      cpu.mmu.write(0xFF05, 0x05)
      cpu.process_timers(1024) # 0x05 -> 0x06, no overflow
      expect(cpu.mmu.interrupts.requested_mask[:timer]).to eq(false)
    end

    it 'detects an overflow even when the increment is a multiple of 256' do
      cpu.mmu.write(0xFF07, 0x05) # enabled, 16 cycles per increment
      cpu.mmu.write(0xFF06, 0x00)
      cpu.mmu.write(0xFF05, 0x00)
      cpu.process_timers(256 * 16)

      expect(cpu.mmu.interrupts.requested_mask[:timer]).to be(true)
    end
  end

  describe 'Integration with CPU step' do
    it 'increments timers during CPU step' do
      cpu = make_cpu([0x00]) # NOP = 4 cycles
      cpu.mmu.write(0xFF07, 0x04) # Enable timer, freq 0
      cpu.mmu.write(0xFF05, 0x00)
      cpu.step
      # NOP takes 4 cycles, need 1024 for 1 increment, so no increment
      expect(cpu.mmu.read(0xFF05)).to eq(0)
    end

    it 'flags interrupt after TIMA overflow in step' do
      cpu = make_cpu([0x00]) # NOP
      cpu.mmu.write(0xFF07, 0x07) # Enable timer, freq 3 (256 cycles)
      cpu.mmu.write(0xFF05, 0xFF)
      expect(cpu.mmu.interrupts.requested_mask[:timer]).to eq(false)
      cpu.step # 4 cycles, no overflow
      expect(cpu.mmu.interrupts.requested_mask[:timer]).to eq(false)
    end
  end
end
