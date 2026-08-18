require_relative '../lib/mmu'
require_relative '../lib/key_state'

RSpec.describe MMU do
  # --- read: direct semantic checks against the known GameBoy memory map ---
  describe '#read' do
    subject(:mmu) { build_mmu }

    it 'reads ROM bytes directly' do
      rom = build_rom
      rom[0x0000] = 0xAB
      rom[0x7FFF] = 0xCD
      m = build_mmu(rom:)
      expect(m.read(0x0000)).to eq(0xAB)
      expect(m.read(0x7FFF)).to eq(0xCD)
    end

    it 'reads VRAM when accessible' do
      mmu.write(0x8000, 0x11)
      mmu.write(0x9FFF, 0x22)
      expect(mmu.read(0x8000)).to eq(0x11)
      expect(mmu.read(0x9FFF)).to eq(0x22)
    end

    it 'returns 0xFF for VRAM when inaccessible' do
      mmu.write(0x8000, 0x11)
      mmu.set_accessible_memory(vram: false)
      expect(mmu.read(0x8000)).to eq(0xFF)
    end

    it 'returns 0xFF for unmapped external RAM (0xA000-0xBFFF)' do
      expect(mmu.read(0xA000)).to eq(0xFF)
      expect(mmu.read(0xBFFF)).to eq(0xFF)
    end

    it 'reads WRAM' do
      mmu.write(0xC000, 0x33)
      mmu.write(0xDFFF, 0x44)
      expect(mmu.read(0xC000)).to eq(0x33)
      expect(mmu.read(0xDFFF)).to eq(0x44)
    end

    it 'returns 0xFF for unmapped echo RAM (0xE000-0xFDFF)' do
      expect(mmu.read(0xE000)).to eq(0xFF)
      expect(mmu.read(0xFDFF)).to eq(0xFF)
    end

    it 'returns 0xFF for the OAM range (stubbed)' do
      expect(mmu.read(0xFE00)).to eq(0xFF)
      expect(mmu.read(0xFE9F)).to eq(0xFF)
    end

    it 'returns 0xFF for the empty range after OAM (0xFEA0-0xFEFF)' do
      expect(mmu.read(0xFEA0)).to eq(0xFF)
      expect(mmu.read(0xFEFF)).to eq(0xFF)
    end

    it 'returns 0xFF for joypad register when no KeyState is set' do
      expect(mmu.read(0xFF00)).to eq(0xFF)
    end

    it 'reads pressed direction buttons through the joypad register' do
      require_relative '../lib/sdl_loader'
      ks = KeyState.new
      ks.update(SDL::SCANCODE_RIGHT, true)
      mmu.set_key_state(ks)
      mmu.write(0xFF00, 0xEF) # select direction
      expect(mmu.read(0xFF00)).to eq(0xFE) # bit 0 cleared
    end

    it 'reads both direction and button state when both select lines are active (real hardware allows this)' do
      require_relative '../lib/sdl_loader'
      ks = KeyState.new
      ks.update(SDL::SCANCODE_RETURN, true) # Start
      ks.update(SDL::SCANCODE_SPACE, true)  # Select
      ks.update(SDL::SCANCODE_RIGHT, true)
      mmu.set_key_state(ks)
      mmu.write(0xFF00, 0xCF) # bit4 and bit5 both cleared: select direction AND button
      # bit0 (Right/A) cleared, bit2 (Up/Select) cleared, bit3 (Down/Start) cleared
      expect(mmu.read(0xFF00)).to eq(0b1111_0010)
    end

    it 'reads/writes generic IO registers' do
      mmu.write(0xFF01, 0x55)
      mmu.write(0xFF7F, 0x66)
      expect(mmu.read(0xFF01)).to eq(0x55)
      expect(mmu.read(0xFF7F)).to eq(0x66)
    end

    it 'reads DIV like any other IO register' do
      mmu.write(0xFF04, 0x42, force: true)
      expect(mmu.read(0xFF04)).to eq(0x42)
    end

    it 'reads HRAM' do
      mmu.write(0xFF80, 0x77)
      mmu.write(0xFFFE, 0x88)
      expect(mmu.read(0xFF80)).to eq(0x77)
      expect(mmu.read(0xFFFE)).to eq(0x88)
    end

    it 'reads IE (0xFFFF) sharing the HRAM backing array' do
      mmu.write(0xFFFF, 0x99)
      expect(mmu.read(0xFFFF)).to eq(0x99)
      # HRAM and IE must not collide with each other
      mmu.write(0xFF80, 0x01)
      expect(mmu.read(0xFFFF)).to eq(0x99)
    end
  end

  # --- write: direct semantic checks ---
  describe '#write' do
    subject(:mmu) { build_mmu }

    it 'does not increment vram_version when VRAM is inaccessible' do
      mmu.set_accessible_memory(vram: false)
      expect { mmu.write(0x8000, 0x11) }.not_to(change { mmu.vram_version })
    end

    it 'increments vram_version on VRAM write when accessible' do
      expect { mmu.write(0x8000, 0x11) }.to change { mmu.vram_version }.by(1)
    end

    it 'writes are read-only for ROM addresses' do
      mmu.write(0x0000, 0xAB)
      expect(mmu.read(0x0000)).to eq(0x00) # untouched ROM byte
    end

    it 'ignores writes to unmapped external/echo RAM' do
      mmu.write(0xA000, 0xAB)
      mmu.write(0xE000, 0xAB)
      expect(mmu.read(0xA000)).to eq(0xFF)
      expect(mmu.read(0xE000)).to eq(0xFF)
    end

    it 'writes OAM and it is visible through read_oams' do
      mmu.write(0xFE00, 0x12)
      expect(mmu.read_oams[0]).to eq(0x12)
    end

    it 'does not write OAM when oam_accessible is false' do
      mmu.write(0xFE00, 0x12)
      mmu.set_accessible_memory(oam: false)
      mmu.write(0xFE00, 0x99)
      expect(mmu.read_oams[0]).to eq(0x12)
    end

    it 'ignores writes to the empty range after OAM (0xFEA0-0xFEFF)' do
      before_oams = mmu.read_oams.dup
      mmu.write(0xFEA0, 0x99)
      expect(mmu.read_oams).to eq(before_oams)
    end

    it 'sets inputs_selector to :direction' do
      mmu.write(0xFF00, 0xEF) # bit4=0
      expect(mmu.instance_variable_get(:@inputs_selector)).to eq(:direction)
    end

    it 'sets inputs_selector to :button' do
      mmu.write(0xFF00, 0xDF) # bit5=0
      expect(mmu.instance_variable_get(:@inputs_selector)).to eq(:button)
    end

    it 'sets inputs_selector to :both when bit4 and bit5 are both cleared' do
      mmu.write(0xFF00, 0xCF) # bit4=0, bit5=0
      expect(mmu.instance_variable_get(:@inputs_selector)).to eq(:both)
    end

    it 'resets DIV to 0 on plain write, regardless of value written' do
      mmu.write(0xFF04, 0x42, force: true)
      mmu.write(0xFF04, 0x99) # not forced
      expect(mmu.read(0xFF04)).to eq(0x00)
    end

    it 'keeps the written value on DIV when force: true' do
      mmu.write(0xFF04, 0x42, force: true)
      expect(mmu.read(0xFF04)).to eq(0x42)
    end

    it 'signals a DIV-APU increment on bit 4 falling edge' do
      mmu.write(0xFF04, 0b0001_0000, force: true) # bit4 = 1
      mmu.write(0xFF04, 0b0000_0000, force: true) # bit4 = 0 -> falling edge
      expect(mmu.consume_div_apu_increment).to eq(true)
    end

    it 'does not signal a DIV-APU increment when bit 4 does not fall' do
      mmu.write(0xFF04, 0b0000_0000, force: true)
      mmu.write(0xFF04, 0b0001_0000, force: true) # rising edge
      expect(mmu.consume_div_apu_increment).to eq(false)
    end

    it 'marks APU registers dirty when written' do
      mmu.write(APU::REGISTERS[:nr52], 0x80)
      expect(mmu.send(:dirty_apu_registers)).to have_key(APU::REGISTERS[:nr52])
    end

    it 'does not mark non-APU IO registers dirty' do
      mmu.write(0xFF01, 0x01) # serial data, not an APU register
      expect(mmu.send(:dirty_apu_registers)).to be_empty
    end

    it 'writes HRAM' do
      mmu.write(0xFF80, 0x77)
      expect(mmu.read(0xFF80)).to eq(0x77)
    end

    it 'writes IE (0xFFFF)' do
      mmu.write(0xFFFF, 0x1F)
      expect(mmu.read(0xFFFF)).to eq(0x1F)
    end

    it 'triggers a DMA transfer when writing a non-zero value to ADDR_DMA' do
      rom = build_rom(bytes: [0xAA], at: 0x0100)
      m = build_mmu(rom:)
      m.write(MMU::ADDR_DMA, 0x01) # source = 0x0100 (ROM)
      expect(m.read_oams[0]).to eq(0xAA)
    end

    it 'does not trigger DMA when writing 0 to ADDR_DMA (matches existing behavior)' do
      rom = build_rom(bytes: [0xAA])
      m = build_mmu(rom:)
      m.write(MMU::ADDR_DMA, 0x00)
      expect(m.read_oams[0]).to eq(0xFF) # untouched, DMA did not run
    end
  end

  describe 'serial transfer (debug_config[:mmu_serial])' do
    it 'completes the transfer instantly and records the byte when enabled' do
      m = build_mmu(debug_config: { mmu_serial: true })
      m.write(MMU::ADDR_SB, 'A'.ord)
      m.write(MMU::ADDR_SC, 0x81) # bit 7 = transfer start, bit 0 = internal clock

      expect(m.serial_output).to eq('A')
      expect(m.read(MMU::ADDR_SC) & 0x80).to eq(0) # bit 7 cleared: transfer "done"
    end

    it 'does nothing special when disabled (default behavior)' do
      m = build_mmu
      m.write(MMU::ADDR_SB, 'A'.ord)
      m.write(MMU::ADDR_SC, 0x81)

      expect(m.serial_output).to be_nil
      expect(m.read(MMU::ADDR_SC) & 0x80).not_to eq(0) # bit 7 left untouched
    end
  end
end
