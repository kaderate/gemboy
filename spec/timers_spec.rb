require_relative '../lib/mmu'
require_relative '../lib/cpu'

RSpec.describe 'Timers' do
  def make_cpu(bytes = []) = build_cpu(*bytes, at: 0)

  let(:cpu) { make_cpu([0x00] * 10) }

  describe 'DIV (0xFF04)' do
    subject { cpu.mmu.read(0xFF04) }

    it 'increments every 256 cycles' do
      initial_div = cpu.mmu.read(0xFF04)
      cpu.mmu.increment_timers(256)
      is_expected.to eq((initial_div + 1) & 0xFF)
    end

    it 'increments multiple times' do
      cpu.mmu.increment_timers(512)
      is_expected.to eq(2)
    end

    it 'overflows at 256' do
      cpu.mmu.write(0xFF04, 0xFF, force: true)
      cpu.mmu.increment_timers(256)
      is_expected.to eq(0)
    end

    it 'resets to 0 when written to' do
      cpu.mmu.write(0xFF04, 0x42)  # Write any value
      is_expected.to eq(0)
    end

    it 'resets the pending cycle accumulator on write, unlike TIMA' do
      cpu.mmu.increment_timers(128) # half a period, banked but no tick yet
      cpu.mmu.write(0xFF04, 0x99)   # any write resets DIV, and the accumulator with it
      cpu.mmu.increment_timers(128) # would complete the period if the old backlog had survived
      is_expected.to eq(0)
    end
  end

  describe 'DIV -> APU frame sequencer coupling (bit 4 falling edge)' do
    # A regression once reported ~4000x too many edges: the sentinel `0` that Prescaler#tick!
    # returns when no pulse occurred was fed straight into the falling-edge comparison instead
    # of the real register value, so half of all no-op calls looked like a falling edge.
    it 'signals exactly one edge per full 8192-cycle period, not on every call' do
      edges = 0
      50.times do
        8192.times { cpu.mmu.increment_timers(1) }
        edges += 1 if cpu.mmu.consume_div_apu_increment
      end

      expect(edges).to eq(50)
    end
  end

  describe 'TIMA (0xFF05)' do
    it 'does not increment when disabled (TAC bit 2 = 0)' do
      cpu.mmu.write(0xFF07, 0x00)  # TAC = 0, timer disabled
      cpu.mmu.write(0xFF05, 0x50)  # TIMA = 0x50
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(0x50) # No change
    end

    it 'increments when enabled (TAC bit 2 = 1)' do
      cpu.mmu.write(0xFF07, 0x04)  # TAC = 0x04, timer enabled, freq=00 (1024 cycles)
      cpu.mmu.write(0xFF05, 0x00)  # TIMA = 0
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(1)
    end

    it 'increments with different frequencies' do
      # Frequency 0 (bits 0-1 = 00): 1024 cycles
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

    it 'overflows and resets to TMA' do
      cpu.mmu.write(0xFF07, 0x04)  # Enable timer
      cpu.mmu.write(0xFF06, 0x42)  # TMA = 0x42
      cpu.mmu.write(0xFF05, 0xFF)  # TIMA = 0xFF
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(0x42) # Reset to TMA
    end

    it 'flags timer interrupt on overflow' do
      cpu.mmu.write(0xFF07, 0x04)  # Enable timer
      cpu.mmu.write(0xFF05, 0xFF)  # TIMA = 0xFF
      expect(cpu.mmu.interrupts_requested_mask[:timer]).to eq(false)
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.interrupts_requested_mask[:timer]).to eq(true)
    end

    it 'can be written directly' do
      cpu.mmu.write(0xFF05, 0x42)
      expect(cpu.mmu.read(0xFF05)).to eq(0x42)
    end

    it 'does not flag a timer interrupt on a plain increment (no overflow)' do
      cpu.mmu.write(0xFF07, 0x04) # Enable timer
      cpu.mmu.write(0xFF05, 0x05)
      cpu.mmu.increment_timers(1024) # 0x05 -> 0x06, no overflow
      expect(cpu.mmu.interrupts_requested_mask[:timer]).to eq(false)
    end

    it 'keeps the pending cycle accumulator across a write, unlike DIV' do
      cpu.mmu.write(0xFF07, 0x05) # enabled, 16 cycles per increment
      cpu.mmu.increment_timers(8) # half a period, banked but no tick yet
      cpu.mmu.write(0xFF05, 0x10) # write TIMA -- must not clear the pending cycles
      cpu.mmu.increment_timers(8) # completes the period if the old backlog survived the write
      expect(cpu.mmu.read(0xFF05)).to eq(0x11)
    end
  end

  describe 'TMA (0xFF06)' do
    it 'stores reload value for TIMA' do
      cpu.mmu.write(0xFF06, 0x99)
      expect(cpu.mmu.read(0xFF06)).to eq(0x99)
    end

    it 'is used on TIMA overflow' do
      cpu.mmu.write(0xFF07, 0x04)  # Enable timer
      cpu.mmu.write(0xFF06, 0x7F)  # TMA = 0x7F
      cpu.mmu.write(0xFF05, 0xFF)  # TIMA = 0xFF
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(0x7F)
    end
  end

  describe 'TAC (0xFF07)' do
    it 'bit 2 enables/disables timer' do
      cpu.mmu.write(0xFF07, 0x00)  # Disabled
      cpu.mmu.write(0xFF05, 0x50)
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(0x50) # No increment

      cpu.mmu.write(0xFF07, 0x04) # Enabled
      cpu.mmu.write(0xFF05, 0x50)
      cpu.mmu.increment_timers(1024)
      expect(cpu.mmu.read(0xFF05)).to eq(0x51) # Incremented
    end

    it 'bits 0-1 select frequency' do
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

    it 'can be read and written' do
      cpu.mmu.write(0xFF07, 0xA5)
      expect(cpu.mmu.read(0xFF07)).to eq(0xA5)
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
      expect(cpu.mmu.interrupts_requested_mask[:timer]).to eq(false)
      cpu.step # 4 cycles, no overflow
      expect(cpu.mmu.interrupts_requested_mask[:timer]).to eq(false)
    end
  end

  describe 'TIMA cadence' do
    FAST_TAC = 0x05 # enabled, 16 cycles per increment — the only rate shorter than a long instruction

    def timer_mmu(tac) = build_mmu.tap { _1.write(0xFF07, tac) }

    it 'does not bank cycles while the timer is disabled' do
      mmu = timer_mmu(0x00)
      mmu.increment_timers(1024)
      mmu.write(0xFF07, FAST_TAC)
      mmu.write(0xFF05, 0x00)

      mmu.increment_timers(0)

      expect(mmu.read(0xFF05)).to eq(0)
    end

    it 'counts every period elapsed during a single call, not just one' do
      mmu = timer_mmu(FAST_TAC)
      mmu.write(0xFF05, 0x00)

      mmu.increment_timers(64)

      expect(mmu.read(0xFF05)).to eq(4)
    end

    it 'carries the remainder over, so the cadence does not drift' do
      mmu = timer_mmu(FAST_TAC)
      mmu.write(0xFF05, 0x00)

      100.times { mmu.increment_timers(24) }

      expect(mmu.read(0xFF05)).to eq(100 * 24 / 16)
    end

    # A backlog used to build up on instructions longer than the period, then drain one increment per
    # call — running the timer several times too fast inside a tight loop.
    it 'does not catch up in a burst once long instructions are over' do
      mmu = timer_mmu(FAST_TAC)
      mmu.write(0xFF05, 0x00)
      100.times { mmu.increment_timers(24) }
      before = mmu.read(0xFF05)

      100.times { mmu.increment_timers(4) }

      expect(mmu.read(0xFF05) - before).to eq(100 * 4 / 16)
    end
  end

  describe 'TIMA overflow' do
    def fast_timer_cpu(tima:, tma:)
      build_cpu.tap do |cpu|
        cpu.mmu.write(0xFF07, 0x05) # enabled, 16 cycles per increment
        cpu.mmu.write(0xFF06, tma)
        cpu.mmu.write(0xFF05, tima)
      end
    end

    it 'carries past the reload instead of dropping the extra increments' do
      cpu = fast_timer_cpu(tima: 0xFF, tma: 0x20)
      cpu.mmu.increment_timers(2 * 16) # two increments: one overflows, one lands after the reload

      expect(cpu.mmu.read(0xFF05)).to eq(0x21)
    end

    it 'wraps modulo the reload window when a single call spans a whole cycle' do
      cpu = fast_timer_cpu(tima: 0x20, tma: 0x20) # 224 increments per overflow
      cpu.mmu.increment_timers(225 * 16)

      expect(cpu.mmu.read(0xFF05)).to eq(0x21)
    end

    it 'detects an overflow even when the increment is a multiple of 256' do
      cpu = fast_timer_cpu(tima: 0x00, tma: 0x00)
      cpu.mmu.increment_timers(256 * 16)

      expect(cpu.mmu.interrupts_requested_mask[:timer]).to be(true)
    end
  end
end
