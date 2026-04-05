require_relative '../lib/mmu'
require_relative '../lib/cpu'

RSpec.describe "Timers" do
  def make_cpu(bytes = [])
    rom = Array.new(0x8000, 0x00)
    bytes.each_with_index { |b, i| rom[i] = b }
    mmu = MMU.new(rom)
    CPU.new(mmu, logger: nil)
  end

  describe "DIV (0xFF04)" do
    it "increments every 256 cycles" do
      cpu = make_cpu([0x00] * 10)
      initial_div = cpu.mmu.read(0xFF04)
      cpu.mmu.increment_timers(256)
      expect(cpu.mmu.read(0xFF04)).to eq((initial_div + 1) & 0xFF)
    end

    it "increments multiple times" do
      cpu = make_cpu([0x00] * 10)
      cpu.mmu.increment_timers(512)  # 512 / 256 = 2 increments
      expect(cpu.mmu.read(0xFF04)).to eq(2)
    end

    it "overflows at 256" do
      cpu = make_cpu([0x00] * 10)
      cpu.mmu.write(0xFF04, 0xFF, force: true)
      cpu.mmu.increment_timers(256)
      expect(cpu.mmu.read(0xFF04)).to eq(0)
    end

    it "resets to 0 when written to" do
      cpu = make_cpu([0x00] * 10)
      cpu.mmu.write(0xFF04, 0x42)  # Write any value
      expect(cpu.mmu.read(0xFF04)).to eq(0)
    end
  end

  describe "TIMA (0xFF05)" do
    it "does not increment when disabled (TAC bit 2 = 0)" do
      cpu = make_cpu([0x00] * 10)
      cpu.mmu.write(0xFF07, 0x00)  # TAC = 0, timer disabled
      cpu.mmu.write(0xFF05, 0x50)  # TIMA = 0x50
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(0x50)  # No change
    end

    it "increments when enabled (TAC bit 2 = 1)" do
      cpu = make_cpu([0x00] * 10)
      cpu.mmu.write(0xFF07, 0x04)  # TAC = 0x04, timer enabled, freq=00 (1024 cycles)
      cpu.mmu.write(0xFF05, 0x00)  # TIMA = 0
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(1)
    end

    it "increments with different frequencies" do
      # Frequency 0 (bits 0-1 = 00): 1024 cycles
      cpu = make_cpu([0x00] * 10)
      cpu.mmu.write(0xFF07, 0x04)
      cpu.mmu.write(0xFF05, 0x00)
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(1)

      # Frequency 1 (bits 0-1 = 01): 16 cycles
      cpu.mmu.write(0xFF07, 0x05)
      cpu.mmu.write(0xFF05, 0x00)
      cpu.mmu.increment_timers(16)
      expect(cpu.mmu.read(0xFF05)).to eq(1)

      # Frequency 2 (bits 0-1 = 10): 64 cycles
      cpu.mmu.write(0xFF07, 0x06)
      cpu.mmu.write(0xFF05, 0x00)
      cpu.mmu.increment_timers(64)
      expect(cpu.mmu.read(0xFF05)).to eq(1)

      # Frequency 3 (bits 0-1 = 11): 256 cycles
      cpu.mmu.write(0xFF07, 0x07)
      cpu.mmu.write(0xFF05, 0x00)
      cpu.mmu.increment_timers(256)
      expect(cpu.mmu.read(0xFF05)).to eq(1)
    end

    it "overflows and resets to TMA" do
      cpu = make_cpu([0x00] * 10)
      cpu.mmu.write(0xFF07, 0x04)  # Enable timer
      cpu.mmu.write(0xFF06, 0x42)  # TMA = 0x42
      cpu.mmu.write(0xFF05, 0xFF)  # TIMA = 0xFF
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(0x42)  # Reset to TMA
    end

    it "flags timer interrupt on overflow" do
      cpu = make_cpu([0x00] * 10)
      cpu.mmu.write(0xFF07, 0x04)  # Enable timer
      cpu.mmu.write(0xFF05, 0xFF)  # TIMA = 0xFF
      expect(cpu.mmu.interrupts_requested_mask[:timer]).to eq(false)
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.interrupts_requested_mask[:timer]).to eq(true)
    end

    it "can be written directly" do
      cpu = make_cpu([0x00] * 10)
      cpu.mmu.write(0xFF05, 0x42)
      expect(cpu.mmu.read(0xFF05)).to eq(0x42)
    end
  end

  describe "TMA (0xFF06)" do
    it "stores reload value for TIMA" do
      cpu = make_cpu([0x00] * 10)
      cpu.mmu.write(0xFF06, 0x99)
      expect(cpu.mmu.read(0xFF06)).to eq(0x99)
    end

    it "is used on TIMA overflow" do
      cpu = make_cpu([0x00] * 10)
      cpu.mmu.write(0xFF07, 0x04)  # Enable timer
      cpu.mmu.write(0xFF06, 0x7F)  # TMA = 0x7F
      cpu.mmu.write(0xFF05, 0xFF)  # TIMA = 0xFF
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(0x7F)
    end
  end

  describe "TAC (0xFF07)" do
    it "bit 2 enables/disables timer" do
      cpu = make_cpu([0x00] * 10)
      cpu.mmu.write(0xFF07, 0x00)  # Disabled
      cpu.mmu.write(0xFF05, 0x50)
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(0x50)  # No increment

      cpu.mmu.write(0xFF07, 0x04)  # Enabled
      cpu.mmu.write(0xFF05, 0x50)
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(0x51)  # Incremented
    end

    it "bits 0-1 select frequency" do
      cpu = make_cpu([0x00] * 10)
      
      # TAC = 0x04 (freq 0, 1024 cycles)
      cpu.mmu.write(0xFF07, 0x04)
      cpu.mmu.write(0xFF05, 0x00)
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(1)

      # TAC = 0x05 (freq 1, 16 cycles)
      cpu.mmu.write(0xFF07, 0x05)
      cpu.mmu.write(0xFF05, 0x00)
      cpu.mmu.increment_timers(16)
      expect(cpu.mmu.read(0xFF05)).to eq(1)
    end

    it "can be read and written" do
      cpu = make_cpu([0x00] * 10)
      cpu.mmu.write(0xFF07, 0xA5)
      expect(cpu.mmu.read(0xFF07)).to eq(0xA5)
    end
  end

  describe "Integration with CPU step" do
    it "increments timers during CPU step" do
      cpu = make_cpu([0x00])  # NOP = 4 cycles
      cpu.mmu.write(0xFF07, 0x04)  # Enable timer, freq 0
      cpu.mmu.write(0xFF05, 0x00)
      cpu.step
      # NOP takes 4 cycles, need 1024 for 1 increment, so no increment
      expect(cpu.mmu.read(0xFF05)).to eq(0)
    end

    it "flags interrupt after TIMA overflow in step" do
      cpu = make_cpu([0x00])  # NOP
      cpu.mmu.write(0xFF07, 0x07)  # Enable timer, freq 3 (256 cycles)
      cpu.mmu.write(0xFF05, 0xFF)
      expect(cpu.mmu.interrupts_requested_mask[:timer]).to eq(false)
      cpu.step  # 4 cycles, no overflow
      expect(cpu.mmu.interrupts_requested_mask[:timer]).to eq(false)
    end
  end
end
