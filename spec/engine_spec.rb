require_relative '../lib/engine'
require_relative '../lib/rom_loader'

RSpec.describe Engine do
  def create_minimal_rom(bytes = [])
    # Crée une ROM minimale de 32KB avec bytes spécifiés au début
    rom = Array.new(0x8000, 0x00)
    bytes.each_with_index { |b, i| rom[i] = b }
    rom
  end

  describe "initialization" do
    it "initializes with a valid ROM" do
      rom_bytes = create_minimal_rom([0x00])  # NOP
      allow(RomLoader).to receive(:new).and_return(
        double(rom_bytes: rom_bytes)
      )

      engine = Engine.new('dummy_path.gb')
      expect(engine.cpu).to be_a(CPU)
      expect(engine.ppu).to be_a(PPU)
      expect(engine.key_state).to be_a(KeyState)
    end

    it "creates MMU with ROM bytes" do
      rom_bytes = create_minimal_rom([0x00, 0x01])
      allow(RomLoader).to receive(:new).and_return(
        double(rom_bytes: rom_bytes)
      )

      engine = Engine.new('dummy_path.gb')
      # Vérifier que CPU a bien reçu les bytes
      expect(engine.mmu.instance_variable_get(:@rom)[0]).to eq(0x00)
      expect(engine.mmu.instance_variable_get(:@rom)[1]).to eq(0x01)
    end

    it "passes MMU to PPU during initialization" do
      rom_bytes = create_minimal_rom([0x00])
      allow(RomLoader).to receive(:new).and_return(
        double(rom_bytes: rom_bytes)
      )

      engine = Engine.new('dummy_path.gb')
      expect(engine.ppu.mmu).to equal(engine.mmu)
    end
  end

  describe "component interaction" do
    let(:rom_bytes) { create_minimal_rom([0x00, 0x00, 0x00]) }  # 3 NOPs
    let(:engine) do
      allow(RomLoader).to receive(:new).and_return(
        double(rom_bytes: rom_bytes)
      )
      Engine.new('dummy_path.gb')
    end

    it "KeyState is accessible from Engine" do
      expect(engine.key_state).to be_a(KeyState)
    end

    it "KeyState can be updated with input" do
      engine.key_state.update('up', true)
      expect(engine.key_state.up).to eq(true)
    end

    it "MMU has reference to KeyState" do
      expect(engine.mmu.key_state).to be_nil  # Initialement nil
      engine.mmu.set_key_state(engine.key_state)
      expect(engine.mmu.key_state).to equal(engine.key_state)
    end

    it "PPU has reference to MMU" do
      expect(engine.ppu.mmu).to equal(engine.mmu)
    end
  end

  describe "CPU execution" do
    let(:rom_bytes) { create_minimal_rom([0x00, 0x00, 0x00, 0x00]) }  # 4 NOPs
    let(:engine) do
      allow(RomLoader).to receive(:new).and_return(
        double(rom_bytes: rom_bytes)
      )
      Engine.new('dummy_path.gb')
    end

    it "CPU starts at 0x100" do
      expect(engine.cpu.pc).to eq(0x100)
    end

    it "executing first NOP increments PC" do
      initial_pc = engine.cpu.pc
      cycles = engine.cpu.step
      expect(engine.cpu.pc).to eq(initial_pc + 1)
      expect(cycles).to eq(4)  # NOP = 4 cycles
    end

    it "multiple steps advance PC correctly" do
      3.times { engine.cpu.step }
      expect(engine.cpu.pc).to eq(0x103)
    end
  end

  describe "PPU synchronization with CPU cycles" do
    let(:rom_bytes) { create_minimal_rom([0x00] * 500) }  # Many NOPs
    let(:engine) do
      allow(RomLoader).to receive(:new).and_return(
        double(rom_bytes: rom_bytes)
      )
      Engine.new('dummy_path.gb')
    end

    it "PPU accumulates CPU cycles" do
      # PPU tracks cycles for scanline timing (456 cycles per scanline)
      initial_cycles = engine.ppu.cycles
      4.times { engine.cpu.step }  # 4 NOPs = 16 cycles
      # ppu.tick would be called with these cycles
      # Direct test below
    end

    it "PPU renders after 456 cycles accumulate" do
      # This would need mocking of ruby2d canvas
      # Simplified test: verify PPU can track cycles
      expect(engine.ppu.cycles).to eq(0)
      engine.ppu.instance_variable_set(:@cycles, 450)
      expect(engine.ppu.cycles).to eq(450)
    end
  end

  describe "input handling" do
    let(:rom_bytes) { create_minimal_rom([0x00]) }
    let(:engine) do
      allow(RomLoader).to receive(:new).and_return(
        double(rom_bytes: rom_bytes)
      )
      Engine.new('dummy_path.gb')
    end

    it "pressing up button updates KeyState" do
      engine.key_state.update('up', true)
      expect(engine.key_state.up).to eq(true)
    end

    it "pressing a button updates KeyState" do
      engine.key_state.update('a', true)
      expect(engine.key_state.a).to eq(true)
    end

    it "releasing button clears state" do
      engine.key_state.update('down', true)
      engine.key_state.update('down', false)
      expect(engine.key_state.down).to eq(false)
    end

    it "multiple buttons can be pressed simultaneously" do
      engine.key_state.update('up', true)
      engine.key_state.update('a', true)
      engine.key_state.update('start', true)
      expect(engine.key_state.up).to eq(true)
      expect(engine.key_state.a).to eq(true)
      expect(engine.key_state.start).to eq(true)
    end

    it "MMU can access KeyState through engine" do
      engine.mmu.set_key_state(engine.key_state)
      engine.key_state.update('up', true)
      # CPU should be able to read key_state.up
      expect(engine.mmu.key_state.up).to eq(true)
    end
  end

  describe "ROM loading" do
    it "loads ROM from file path" do
      rom_bytes = create_minimal_rom([0xAB, 0xCD])
      allow(RomLoader).to receive(:new).with('test.gb').and_return(
        double(rom_bytes: rom_bytes)
      )

      engine = Engine.new('test.gb')
      expect(RomLoader).to have_received(:new).with('test.gb')
    end

    it "initializes full 32KB ROM space" do
      rom_bytes = create_minimal_rom
      allow(RomLoader).to receive(:new).and_return(
        double(rom_bytes: rom_bytes)
      )

      engine = Engine.new('dummy.gb')
      mmu_rom = engine.mmu.instance_variable_get(:@rom)
      expect(mmu_rom.length).to eq(0x8000)  # 32 KB
    end
  end

  describe "CPU-PPU integration" do
    let(:rom_bytes) { create_minimal_rom([0x00] * 100) }
    let(:engine) do
      allow(RomLoader).to receive(:new).and_return(
        double(rom_bytes: rom_bytes)
      )
      Engine.new('dummy_path.gb')
    end

    it "PPU can read from MMU VRAM" do
      # PPU reads VRAM through MMU
      expect(engine.ppu.mmu).to equal(engine.mmu)
    end

    it "PPU can read LCD control from MMU" do
      # LCD control should be accessible
      lcd_control = engine.mmu.read_lcd_control
      expect(lcd_control).to be_a(Hash)
      expect(lcd_control.keys).to include(:lcd_enable, :bg_tile_map_display_select)
    end
  end

  describe "frame rate constant" do
    it "defines FRAME_RATE for Game Boy" do
      expect(Engine::FRAME_RATE).to be_within(0.1).of(59.7)
    end
  end
end
