# frozen_string_literal: true

require_relative '../lib/timer'

RSpec.describe Timer do
  subject(:timer) { described_class.new }

  ADDR_DIV = 0xFF04
  ADDR_TIMA = 0xFF05
  ADDR_TMA = 0xFF06
  ADDR_TAC = 0xFF07

  describe 'DIV (0xFF04)' do
    subject { timer.read(ADDR_DIV) }

    it 'increments every 256 cycles' do
      initial_div = timer.read(ADDR_DIV)
      timer.tick!(256)
      is_expected.to eq((initial_div + 1) & 0xFF)
    end

    it 'increments multiple times' do
      timer.tick!(512)
      is_expected.to eq(2)
    end

    it 'overflows at 256' do
      timer.write(ADDR_DIV, 0xFF, force: true)
      timer.tick!(256)
      is_expected.to eq(0)
    end

    it 'resets to 0 when written to' do
      timer.write(ADDR_DIV, 0x42) # Write any value, not forced
      is_expected.to eq(0)
    end

    it 'resets the pending cycle accumulator on write, unlike TIMA' do
      timer.tick!(128) # half a period, banked but no tick yet
      timer.write(ADDR_DIV, 0x99) # any write resets DIV, and the accumulator with it
      timer.tick!(128) # would complete the period if the old backlog had survived
      is_expected.to eq(0)
    end
  end

  describe 'DIV -> APU frame sequencer coupling (bit 4 falling edge)' do
    it 'signals a falling edge' do
      timer.write(ADDR_DIV, 0b0001_0000, force: true) # bit4 = 1
      timer.write(ADDR_DIV, 0b0000_0000, force: true) # bit4 = 0 -> falling edge
      expect(timer.consume_div_increment).to eq(true)
    end

    it 'does not signal an edge on a rising transition' do
      timer.write(ADDR_DIV, 0b0000_0000, force: true)
      timer.write(ADDR_DIV, 0b0001_0000, force: true) # rising edge
      expect(timer.consume_div_increment).to eq(false)
    end

    # A regression once reported ~4000x too many edges: the sentinel `0` that Prescaler#tick!
    # returns when no pulse occurred was fed straight into the falling-edge comparison instead
    # of the real register value, so half of all no-op calls looked like a falling edge.
    it 'signals exactly one edge per full 8192-cycle period, not on every call' do
      edges = 0
      50.times do
        8192.times { timer.tick!(1) }
        edges += 1 if timer.consume_div_increment
      end

      expect(edges).to eq(50)
    end
  end

  describe 'TIMA (0xFF05)' do
    it 'does not increment when disabled (TAC bit 2 = 0)' do
      timer.write(ADDR_TAC, 0x00)  # TAC = 0, timer disabled
      timer.write(ADDR_TIMA, 0x50) # TIMA = 0x50
      timer.tick!(1024)
      expect(timer.read(ADDR_TIMA)).to eq(0x50) # No change
    end

    it 'increments when enabled (TAC bit 2 = 1)' do
      timer.write(ADDR_TAC, 0x04) # TAC = 0x04, timer enabled, freq=00 (1024 cycles)
      timer.write(ADDR_TIMA, 0x00)
      timer.tick!(1024)
      expect(timer.read(ADDR_TIMA)).to eq(1)
    end

    it 'increments with different frequencies' do
      # Frequency 0 (bits 0-1 = 00): 1024 cycles
      timer.write(ADDR_TAC, 0x04)
      timer.write(ADDR_TIMA, 0x00)
      timer.tick!(1024)
      expect(timer.read(ADDR_TIMA)).to eq(1)

      # Frequency 1 (bits 0-1 = 01): 16 cycles
      timer.write(ADDR_TAC, 0x05)
      timer.write(ADDR_TIMA, 0x00)
      timer.tick!(16)
      expect(timer.read(ADDR_TIMA)).to eq(1)

      # Frequency 2 (bits 0-1 = 10): 64 cycles
      timer.write(ADDR_TAC, 0x06)
      timer.write(ADDR_TIMA, 0x00)
      timer.tick!(64)
      expect(timer.read(ADDR_TIMA)).to eq(1)

      # Frequency 3 (bits 0-1 = 11): 256 cycles
      timer.write(ADDR_TAC, 0x07)
      timer.write(ADDR_TIMA, 0x00)
      timer.tick!(256)
      expect(timer.read(ADDR_TIMA)).to eq(1)
    end

    it 'overflows and resets to TMA' do
      timer.write(ADDR_TAC, 0x04) # Enable timer
      timer.write(ADDR_TMA, 0x42)
      timer.write(ADDR_TIMA, 0xFF)
      timer.tick!(1024)
      expect(timer.read(ADDR_TIMA)).to eq(0x42) # Reset to TMA
    end

    it 'returns true from #tick! on overflow' do
      timer.write(ADDR_TAC, 0x04) # Enable timer
      timer.write(ADDR_TIMA, 0xFF)
      expect(timer.tick!(1024)).to eq(true)
    end

    it 'can be written directly' do
      timer.write(ADDR_TIMA, 0x42)
      expect(timer.read(ADDR_TIMA)).to eq(0x42)
    end

    it 'returns false from #tick! on a plain increment (no overflow)' do
      timer.write(ADDR_TAC, 0x04) # Enable timer
      timer.write(ADDR_TIMA, 0x05)
      expect(timer.tick!(1024)).to eq(false) # 0x05 -> 0x06, no overflow
    end

    it 'keeps the pending cycle accumulator across a write, unlike DIV' do
      timer.write(ADDR_TAC, 0x05) # enabled, 16 cycles per increment
      timer.tick!(8) # half a period, banked but no tick yet
      timer.write(ADDR_TIMA, 0x10) # write TIMA -- must not clear the pending cycles
      timer.tick!(8) # completes the period if the old backlog survived the write
      expect(timer.read(ADDR_TIMA)).to eq(0x11)
    end
  end

  describe 'TMA (0xFF06)' do
    it 'stores reload value for TIMA' do
      timer.write(ADDR_TMA, 0x99)
      expect(timer.read(ADDR_TMA)).to eq(0x99)
    end

    it 'is used on TIMA overflow' do
      timer.write(ADDR_TAC, 0x04) # Enable timer
      timer.write(ADDR_TMA, 0x7F)
      timer.write(ADDR_TIMA, 0xFF)
      timer.tick!(1024)
      expect(timer.read(ADDR_TIMA)).to eq(0x7F)
    end
  end

  describe 'TAC (0xFF07)' do
    it 'bit 2 enables/disables timer' do
      timer.write(ADDR_TAC, 0x00) # Disabled
      timer.write(ADDR_TIMA, 0x50)
      timer.tick!(1024)
      expect(timer.read(ADDR_TIMA)).to eq(0x50) # No increment

      timer.write(ADDR_TAC, 0x04) # Enabled
      timer.write(ADDR_TIMA, 0x50)
      timer.tick!(1024)
      expect(timer.read(ADDR_TIMA)).to eq(0x51) # Incremented
    end

    it 'bits 0-1 select frequency' do
      # TAC = 0x04 (freq 0, 1024 cycles)
      timer.write(ADDR_TAC, 0x04)
      timer.write(ADDR_TIMA, 0x00)
      timer.tick!(1024)
      expect(timer.read(ADDR_TIMA)).to eq(1)

      # TAC = 0x05 (freq 1, 16 cycles)
      timer.write(ADDR_TAC, 0x05)
      timer.write(ADDR_TIMA, 0x00)
      timer.tick!(16)
      expect(timer.read(ADDR_TIMA)).to eq(1)
    end

    it 'can be read and written' do
      timer.write(ADDR_TAC, 0xA5)
      expect(timer.read(ADDR_TAC)).to eq(0xA5)
    end
  end

  describe 'TIMA cadence' do
    FAST_TAC = 0x05 # enabled, 16 cycles per increment — the only rate shorter than a long instruction

    def fast_timer
      described_class.new.tap { _1.write(ADDR_TAC, FAST_TAC) }
    end

    it 'does not bank cycles while the timer is disabled' do
      timer = described_class.new.tap { _1.write(ADDR_TAC, 0x00) }
      timer.tick!(1024)
      timer.write(ADDR_TAC, FAST_TAC)
      timer.write(ADDR_TIMA, 0x00)

      timer.tick!(0)

      expect(timer.read(ADDR_TIMA)).to eq(0)
    end

    it 'counts every period elapsed during a single call, not just one' do
      timer = fast_timer
      timer.write(ADDR_TIMA, 0x00)

      timer.tick!(64)

      expect(timer.read(ADDR_TIMA)).to eq(4)
    end

    it 'carries the remainder over, so the cadence does not drift' do
      timer = fast_timer
      timer.write(ADDR_TIMA, 0x00)

      100.times { timer.tick!(24) }

      expect(timer.read(ADDR_TIMA)).to eq(100 * 24 / 16)
    end

    # A backlog used to build up on instructions longer than the period, then drain one increment per
    # call — running the timer several times too fast inside a tight loop.
    it 'does not catch up in a burst once long instructions are over' do
      timer = fast_timer
      timer.write(ADDR_TIMA, 0x00)
      100.times { timer.tick!(24) }
      before = timer.read(ADDR_TIMA)

      100.times { timer.tick!(4) }

      expect(timer.read(ADDR_TIMA) - before).to eq(100 * 4 / 16)
    end
  end

  describe 'TIMA overflow' do
    def fast_timer_with(tima:, tma:)
      described_class.new.tap do |timer|
        timer.write(ADDR_TAC, 0x05) # enabled, 16 cycles per increment
        timer.write(ADDR_TMA, tma)
        timer.write(ADDR_TIMA, tima)
      end
    end

    it 'carries past the reload instead of dropping the extra increments' do
      timer = fast_timer_with(tima: 0xFF, tma: 0x20)
      timer.tick!(2 * 16) # two increments: one overflows, one lands after the reload

      expect(timer.read(ADDR_TIMA)).to eq(0x21)
    end

    it 'wraps modulo the reload window when a single call spans a whole cycle' do
      timer = fast_timer_with(tima: 0x20, tma: 0x20) # 224 increments per overflow
      timer.tick!(225 * 16)

      expect(timer.read(ADDR_TIMA)).to eq(0x21)
    end

    it 'detects an overflow even when the increment is a multiple of 256' do
      timer = fast_timer_with(tima: 0x00, tma: 0x00)
      expect(timer.tick!(256 * 16)).to be(true)
    end
  end
end
