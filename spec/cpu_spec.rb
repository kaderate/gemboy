require_relative '../lib/cpu'

def make_cpu(*bytes)
  rom = Array.new(0x8000, 0x00)
  bytes.each_with_index { |b, i| rom[0x100 + i] = b }
  CPU.new(rom)
end

RSpec.describe CPU do
  # Suppress output during tests
  before { allow($stdout).to receive(:puts) }

  # ---------------------------------------------------------------------------
  # NOP
  # ---------------------------------------------------------------------------
  describe "NOP (0x00)" do
    it "increments PC by 1 and returns 4 cycles" do
      cpu = make_cpu(0x00)
      cycles = cpu.step
      expect(cpu.pc).to eq(0x101)
      expect(cycles).to eq(4)
    end
  end

  # ---------------------------------------------------------------------------
  # LD r8, d8
  # ---------------------------------------------------------------------------
  describe "LD r8, d8" do
    it "LD B, d8 (0x06) loads immediate into B" do
      cpu = make_cpu(0x06, 0x42)
      cycles = cpu.step
      expect(cpu.b).to eq(0x42)
      expect(cpu.pc).to eq(0x102)
      expect(cycles).to eq(8)
    end

    it "LD C, d8 (0x0E) loads immediate into C" do
      cpu = make_cpu(0x0E, 0x11)
      cycles = cpu.step
      expect(cpu.c).to eq(0x11)
      expect(cpu.pc).to eq(0x102)
      expect(cycles).to eq(8)
    end

    it "LD D, d8 (0x16) loads immediate into D" do
      cpu = make_cpu(0x16, 0x22)
      cycles = cpu.step
      expect(cpu.d).to eq(0x22)
      expect(cpu.pc).to eq(0x102)
      expect(cycles).to eq(8)
    end

    it "LD E, d8 (0x1E) loads immediate into E" do
      cpu = make_cpu(0x1E, 0x33)
      cycles = cpu.step
      expect(cpu.e).to eq(0x33)
      expect(cpu.pc).to eq(0x102)
      expect(cycles).to eq(8)
    end

    it "LD H, d8 (0x26) loads immediate into H" do
      cpu = make_cpu(0x26, 0x44)
      cycles = cpu.step
      expect(cpu.h).to eq(0x44)
      expect(cpu.pc).to eq(0x102)
      expect(cycles).to eq(8)
    end

    it "LD L, d8 (0x2E) loads immediate into L" do
      cpu = make_cpu(0x2E, 0x55)
      cycles = cpu.step
      expect(cpu.l).to eq(0x55)
      expect(cpu.pc).to eq(0x102)
      expect(cycles).to eq(8)
    end

    it "LD A, d8 (0x3E) loads immediate into A" do
      cpu = make_cpu(0x3E, 0xFF)
      cycles = cpu.step
      expect(cpu.a).to eq(0xFF)
      expect(cpu.pc).to eq(0x102)
      expect(cycles).to eq(8)
    end
  end

  # ---------------------------------------------------------------------------
  # LD r8, r8
  # ---------------------------------------------------------------------------
  describe "LD r8, r8" do
    it "LD B, C (0x41) copies C into B" do
      cpu = make_cpu(0x41)
      cpu.a = 0
      # set C via LD C, d8
      cpu2 = make_cpu(0x0E, 0x99, 0x41)
      cpu2.step  # LD C, 0x99
      cycles = cpu2.step  # LD B, C
      expect(cpu2.b).to eq(0x99)
      expect(cpu2.pc).to eq(0x103)
      expect(cycles).to eq(4)
    end

    it "LD A, B (0x78) copies B into A" do
      cpu = make_cpu(0x06, 0xAB, 0x78)
      cpu.step  # LD B, 0xAB
      cycles = cpu.step  # LD A, B
      expect(cpu.a).to eq(0xAB)
      expect(cpu.pc).to eq(0x103)
      expect(cycles).to eq(4)
    end

    it "LD (HL), A (0x77) writes A to memory at HL" do
      # LD HL, 0xC000 then LD A, d8 then LD (HL), A
      cpu = make_cpu(0x21, 0x00, 0xC0, 0x3E, 0x7F, 0x77)
      cpu.step  # LD HL, 0xC000
      cpu.step  # LD A, 0x7F
      cycles = cpu.step  # LD (HL), A
      expect(cpu.read(0xC000)).to eq(0x7F)
      expect(cpu.pc).to eq(0x106)
      expect(cycles).to eq(8)
    end

    it "LD A, (HL) (0x7E) reads from memory at HL into A" do
      # LD HL, 0xC000 then write value at 0xC000 then LD A, (HL)
      cpu = make_cpu(0x21, 0x00, 0xC0, 0x7E)
      cpu.step  # LD HL, 0xC000
      cpu.write(0xC000, 0x5A)
      cycles = cpu.step  # LD A, (HL)
      expect(cpu.a).to eq(0x5A)
      expect(cpu.pc).to eq(0x104)
      expect(cycles).to eq(8)
    end

    it "LD C, D (0x4A) copies D into C" do
      cpu = make_cpu(0x16, 0x12, 0x4A)  # LD D, 0x12 ; LD C, D
      cpu.step  # LD D, 0x12
      cycles = cpu.step  # LD C, D
      expect(cpu.c).to eq(0x12)
      expect(cpu.pc).to eq(0x103)
      expect(cycles).to eq(4)
    end

    it "LD D, E (0x53) copies E into D" do
      cpu = make_cpu(0x1E, 0x34, 0x53)  # LD E, 0x34 ; LD D, E
      cpu.step  # LD E, 0x34
      cycles = cpu.step  # LD D, E
      expect(cpu.d).to eq(0x34)
      expect(cpu.pc).to eq(0x103)
      expect(cycles).to eq(4)
    end

    it "LD E, H (0x5C) copies H into E" do
      cpu = make_cpu(0x26, 0x56, 0x5C)  # LD H, 0x56 ; LD E, H
      cpu.step  # LD H, 0x56
      cycles = cpu.step  # LD E, H
      expect(cpu.e).to eq(0x56)
      expect(cpu.pc).to eq(0x103)
      expect(cycles).to eq(4)
    end

    it "LD H, L (0x65) copies L into H" do
      cpu = make_cpu(0x2E, 0x78, 0x65)  # LD L, 0x78 ; LD H, L
      cpu.step  # LD L, 0x78
      cycles = cpu.step  # LD H, L
      expect(cpu.h).to eq(0x78)
      expect(cpu.pc).to eq(0x103)
      expect(cycles).to eq(4)
    end

    it "LD L, A (0x6F) copies A into L" do
      cpu = make_cpu(0x3E, 0x9A, 0x6F)  # LD A, 0x9A ; LD L, A
      cpu.step  # LD A, 0x9A
      cycles = cpu.step  # LD L, A
      expect(cpu.l).to eq(0x9A)
      expect(cpu.pc).to eq(0x103)
      expect(cycles).to eq(4)
    end
  end

  # ---------------------------------------------------------------------------
  # HALT
  # ---------------------------------------------------------------------------
  describe "HALT (0x76)" do
    it "stops the CPU and returns 4 cycles" do
      cpu = make_cpu(0x76)
      cycles = cpu.step
      expect(cpu.running?).to be false
      expect(cpu.pc).to eq(0x101)
      expect(cycles).to eq(4)
    end
  end

  # ---------------------------------------------------------------------------
  # LD r16, d16
  # ---------------------------------------------------------------------------
  describe "LD r16, d16" do
    it "LD BC, d16 (0x01) loads 16-bit immediate into BC" do
      cpu = make_cpu(0x01, 0x34, 0x12)  # little-endian: 0x1234
      cycles = cpu.step
      expect(cpu.bc).to eq(0x1234)
      expect(cpu.b).to eq(0x12)
      expect(cpu.c).to eq(0x34)
      expect(cpu.pc).to eq(0x103)
      expect(cycles).to eq(12)
    end

    it "LD DE, d16 (0x11) loads 16-bit immediate into DE" do
      cpu = make_cpu(0x11, 0x78, 0x56)  # 0x5678
      cycles = cpu.step
      expect(cpu.de).to eq(0x5678)
      expect(cpu.d).to eq(0x56)
      expect(cpu.e).to eq(0x78)
      expect(cpu.pc).to eq(0x103)
      expect(cycles).to eq(12)
    end

    it "LD HL, d16 (0x21) loads 16-bit immediate into HL" do
      cpu = make_cpu(0x21, 0xBC, 0x9A)  # 0x9ABC
      cycles = cpu.step
      expect(cpu.hl).to eq(0x9ABC)
      expect(cpu.h).to eq(0x9A)
      expect(cpu.l).to eq(0xBC)
      expect(cpu.pc).to eq(0x103)
      expect(cycles).to eq(12)
    end
  end

  # ---------------------------------------------------------------------------
  # LD (BC), A
  # ---------------------------------------------------------------------------
  describe "LD (BC), A (0x02)" do
    it "writes A to memory at BC" do
      cpu = make_cpu(0x01, 0x00, 0xC0, 0x3E, 0x55, 0x02)
      cpu.step  # LD BC, 0xC000
      cpu.step  # LD A, 0x55
      cycles = cpu.step  # LD (BC), A
      expect(cpu.read(0xC000)).to eq(0x55)
      expect(cpu.pc).to eq(0x106)
      expect(cycles).to eq(8)
    end
  end

  # ---------------------------------------------------------------------------
  # LD (DE), A
  # ---------------------------------------------------------------------------
  describe "LD (DE), A (0x12)" do
    it "writes A to memory at DE" do
      cpu = make_cpu(0x11, 0x00, 0xC0, 0x3E, 0x88, 0x12)
      cpu.step  # LD DE, 0xC000
      cpu.step  # LD A, 0x88
      cycles = cpu.step  # LD (DE), A
      expect(cpu.read(0xC000)).to eq(0x88)
      expect(cpu.pc).to eq(0x106)
      expect(cycles).to eq(8)
    end
  end

  # ---------------------------------------------------------------------------
  # LDI (HL), A
  # ---------------------------------------------------------------------------
  describe "LDI (HL), A (0x22)" do
    it "writes A to memory at HL and increments HL" do
      cpu = make_cpu(0x21, 0x05, 0xC0, 0x3E, 0xAA, 0x22)
      cpu.step  # LD HL, 0xC005
      cpu.step  # LD A, 0xAA
      cycles = cpu.step  # LDI (HL), A
      expect(cpu.read(0xC005)).to eq(0xAA)
      expect(cpu.hl).to eq(0xC006)
      expect(cpu.pc).to eq(0x106)
      expect(cycles).to eq(8)
    end

    it "increments HL even when wrapping to 0x0000" do
      cpu = make_cpu(0x21, 0xFF, 0xFF, 0x3E, 0xBB, 0x22)
      cpu.step  # LD HL, 0xFFFF
      cpu.step  # LD A, 0xBB
      cpu.step  # LDI (HL), A
      expect(cpu.hl).to eq(0x0000)
    end
  end

  # ---------------------------------------------------------------------------
  # LDD (HL), A
  # ---------------------------------------------------------------------------
  describe "LDD (HL), A (0x32)" do
    it "writes A to memory at HL and decrements HL" do
      cpu = make_cpu(0x21, 0x10, 0xC0, 0x3E, 0xCC, 0x32)
      cpu.step  # LD HL, 0xC010
      cpu.step  # LD A, 0xCC
      cycles = cpu.step  # LDD (HL), A
      expect(cpu.read(0xC010)).to eq(0xCC)
      expect(cpu.hl).to eq(0xC00F)
      expect(cpu.pc).to eq(0x106)
      expect(cycles).to eq(8)
    end

    it "decrements HL even when wrapping to 0xFFFF" do
      cpu = make_cpu(0x21, 0x00, 0x00, 0x3E, 0xDD, 0x32)
      cpu.step  # LD HL, 0x0000
      cpu.step  # LD A, 0xDD
      cpu.step  # LDD (HL), A
      expect(cpu.hl).to eq(0xFFFF)
    end
  end

  # ---------------------------------------------------------------------------
  # LD (a16), A
  # ---------------------------------------------------------------------------
  describe "LD (a16), A (0xEA)" do
    it "writes A to the given 16-bit address in WRAM" do
      cpu = make_cpu(0x3E, 0xCD, 0xEA, 0x00, 0xC0)
      cpu.step  # LD A, 0xCD
      cycles = cpu.step  # LD (0xC000), A
      expect(cpu.read(0xC000)).to eq(0xCD)
      expect(cpu.pc).to eq(0x105)
      expect(cycles).to eq(16)
    end
  end

  # ---------------------------------------------------------------------------
  # INC HL / INC DE
  # ---------------------------------------------------------------------------
  describe "INC HL (0x23)" do
    it "increments HL by 1" do
      cpu = make_cpu(0x21, 0x00, 0xC0, 0x23)
      cpu.step  # LD HL, 0xC000
      cycles = cpu.step  # INC HL
      expect(cpu.hl).to eq(0xC001)
      expect(cpu.pc).to eq(0x104)
      expect(cycles).to eq(8)
    end

    it "wraps 0xFFFF to 0x0000" do
      cpu = make_cpu(0x21, 0xFF, 0xFF, 0x23)
      cpu.step  # LD HL, 0xFFFF
      cpu.step  # INC HL
      expect(cpu.hl).to eq(0x0000)
    end
  end

  describe "INC DE (0x13)" do
    it "increments DE by 1" do
      cpu = make_cpu(0x11, 0x05, 0x00, 0x13)
      cpu.step  # LD DE, 0x0005
      cycles = cpu.step  # INC DE
      expect(cpu.de).to eq(0x0006)
      expect(cpu.pc).to eq(0x104)
      expect(cycles).to eq(8)
    end

    it "wraps 0xFFFF to 0x0000" do
      cpu = make_cpu(0x11, 0xFF, 0xFF, 0x13)
      cpu.step  # LD DE, 0xFFFF
      cpu.step  # INC DE
      expect(cpu.de).to eq(0x0000)
    end
  end

  # ---------------------------------------------------------------------------
  # DEC B
  # ---------------------------------------------------------------------------
  describe "DEC B (0x05)" do
    it "decrements B by 1 and clears Z flag" do
      cpu = make_cpu(0x06, 0x05, 0x05)
      cpu.step  # LD B, 0x05
      cycles = cpu.step  # DEC B
      expect(cpu.b).to eq(0x04)
      expect(cpu.flag_z).to be false
      expect(cpu.pc).to eq(0x103)
      expect(cycles).to eq(4)
    end

    it "sets Z flag when B decrements to 0" do
      cpu = make_cpu(0x06, 0x01, 0x05)
      cpu.step  # LD B, 0x01
      cpu.step  # DEC B
      expect(cpu.b).to eq(0x00)
      expect(cpu.flag_z).to be true
    end

    it "wraps B=0 to 0xFF and clears Z flag" do
      cpu = make_cpu(0x06, 0x00, 0x05)
      cpu.step  # LD B, 0x00
      cpu.step  # DEC B
      expect(cpu.b).to eq(0xFF)
      expect(cpu.flag_z).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # DEC BC
  # ---------------------------------------------------------------------------
  describe "DEC BC (0x0B)" do
    it "decrements BC by 1 without modifying flags" do
      cpu = make_cpu(0x01, 0x00, 0x01, 0x0B)  # BC = 0x0100
      cpu.step  # LD BC, 0x0100
      cycles = cpu.step  # DEC BC
      expect(cpu.bc).to eq(0x00FF)
      expect(cpu.pc).to eq(0x104)
      expect(cycles).to eq(8)
    end

    it "wraps 0x0000 to 0xFFFF" do
      cpu = make_cpu(0x01, 0x00, 0x00, 0x0B)  # BC = 0x0000
      cpu.step  # LD BC, 0x0000
      cpu.step  # DEC BC
      expect(cpu.bc).to eq(0xFFFF)
    end
  end

  # ---------------------------------------------------------------------------
  # JR NZ, r8
  # ---------------------------------------------------------------------------
  describe "JR NZ, r8 (0x20)" do
    it "jumps with positive offset when Z=false" do
      cpu = make_cpu(0x20, 0x05)  # Z=false by default, offset=5
      cycles = cpu.step
      expect(cpu.pc).to eq(0x100 + 2 + 5)
      expect(cycles).to eq(12)
    end

    it "jumps with negative offset when Z=false" do
      cpu = make_cpu(0x20, 0xFD)  # offset = -3
      cycles = cpu.step
      expect(cpu.pc).to eq(0x100 + 2 - 3)
      expect(cycles).to eq(12)
    end

    it "does not jump when Z=true" do
      cpu = make_cpu(0x20, 0x05)
      cpu.flag_z = true
      cycles = cpu.step
      expect(cpu.pc).to eq(0x102)
      expect(cycles).to eq(8)
    end
  end

  # ---------------------------------------------------------------------------
  # JR r8
  # ---------------------------------------------------------------------------
  describe "JR r8 (0x18)" do
    it "jumps with positive offset" do
      cpu = make_cpu(0x18, 0x03)
      cycles = cpu.step
      expect(cpu.pc).to eq(0x100 + 2 + 3)
      expect(cycles).to eq(12)
    end

    it "jumps with negative offset" do
      cpu = make_cpu(0x18, 0xFA)  # -6
      cycles = cpu.step
      expect(cpu.pc).to eq(0x100 + 2 - 6)
      expect(cycles).to eq(12)
    end

    it "sets @infinite_loop when offset is 0xFE" do
      cpu = make_cpu(0x18, 0xFE)
      cpu.step
      expect(cpu.instance_variable_get(:@infinite_loop)).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # JP a16
  # ---------------------------------------------------------------------------
  describe "JP a16 (0xC3)" do
    it "jumps to the 16-bit address (little-endian)" do
      cpu = make_cpu(0xC3, 0x50, 0x01)  # 0x0150
      cycles = cpu.step
      expect(cpu.pc).to eq(0x0150)
      expect(cycles).to eq(16)
    end
  end
end
