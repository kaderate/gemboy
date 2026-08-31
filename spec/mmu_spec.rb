require_relative '../lib/mmu'
require_relative '../lib/key_state'
require_relative '../lib/screen'

RSpec.describe MMU do
  # --- read: direct semantic checks against the known GameBoy memory map ---
  describe '#read' do
    subject(:mmu) { build_mmu }
    let!(:ppu) { build_ppu(mmu) }

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
      ppu.send(:set_accessible_memory, vram: false)
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
      mmu.joypad.key_state = ks
      mmu.write(0xFF00, 0xEF) # select direction
      expect(mmu.read(0xFF00)).to eq(0xFE) # bit 0 cleared
    end

    it 'reads both direction and button state when both select lines are active (real hardware allows this)' do
      require_relative '../lib/sdl_loader'
      ks = KeyState.new
      ks.update(SDL::SCANCODE_RETURN, true) # Start
      ks.update(SDL::SCANCODE_SPACE, true)  # Select
      ks.update(SDL::SCANCODE_RIGHT, true)
      mmu.joypad.key_state = ks
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

    it 'reads/writes IE (0xFFFF), independent from HRAM' do
      mmu.write(0xFFFF, 0x99)
      expect(mmu.read(0xFFFF)).to eq(0x99)
      mmu.write(0xFF80, 0x01)
      expect(mmu.read(0xFFFF)).to eq(0x99)
    end

    it 'reads KEY1 (0xFF4D) through the speed shifter, in CGB mode' do
      m = build_mmu(cgb: :only)
      m.write(0xFF4D, 0x01) # arm
      expect(m.read(0xFF4D)).to eq(0x01)
    end

    it 'reads KEY1 (0xFF4D) as inert (0xFF) outside CGB mode' do
      mmu.write(0xFF4D, 0x01) # arm attempt, should be a no-op in DMG mode
      expect(mmu.read(0xFF4D)).to eq(0xFF)
    end

    # KEY0, VBK, HDMA1-5, RP, OPRI, SVBK: routed but not yet backed by a real component (owned by
    # later CGB tasks) -- until then, reading any of them is inert (0xFF).
    CGB_PLACEHOLDER_ADDRESSES = [0xFF4C, 0xFF4F, 0xFF51, 0xFF52, 0xFF53, 0xFF54, 0xFF55, 0xFF56,
                                 0xFF6C, 0xFF70].freeze

    CGB_PLACEHOLDER_ADDRESSES.each do |addr|
      it "reads #{format('0x%04X', addr)} as inert (0xFF), routed but not yet implemented" do
        expect(mmu.read(addr)).to eq(0xFF)
      end
    end

    it 'reads BCPS/OCPS/BCPD/OCPD (0xFF68-0xFF6B) as inert (0xFF) outside CGB mode' do
      [0xFF68, 0xFF69, 0xFF6A, 0xFF6B].each { |addr| expect(mmu.read(addr)).to eq(0xFF) }
    end
  end

  # --- write: direct semantic checks ---
  describe '#write' do
    subject(:mmu) { build_mmu }
    let!(:ppu) { build_ppu(mmu) }

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
      expect(ppu.oam_reader.read_oams[0]).to eq(0x12)
    end

    it 'does not write OAM when oam_accessible is false' do
      mmu.write(0xFE00, 0x12)
      ppu.send(:set_accessible_memory, oam: false)
      mmu.write(0xFE00, 0x99)
      expect(ppu.oam_reader.read_oams[0]).to eq(0x12)
    end

    it 'ignores writes to the empty range after OAM (0xFEA0-0xFEFF)' do
      before_oams = ppu.oam_reader.read_oams.dup
      mmu.write(0xFEA0, 0x99)
      expect(ppu.oam_reader.read_oams).to eq(before_oams)
    end

    it 'sets inputs_selector to :direction' do
      mmu.write(0xFF00, 0xEF) # bit4=0
      expect(mmu.joypad.instance_variable_get(:@inputs_selector)).to eq(:direction)
    end

    it 'sets inputs_selector to :button' do
      mmu.write(0xFF00, 0xDF) # bit5=0
      expect(mmu.joypad.instance_variable_get(:@inputs_selector)).to eq(:button)
    end

    it 'sets inputs_selector to :both when bit4 and bit5 are both cleared' do
      mmu.write(0xFF00, 0xCF) # bit4=0, bit5=0
      expect(mmu.joypad.instance_variable_get(:@inputs_selector)).to eq(:both)
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

    it 'hands APU register writes over to the APU rather than storing them itself' do
      mmu.write(APU::REGISTERS[:nr50], 0x77)

      expect(mmu.read(APU::REGISTERS[:nr50])).to eq(0x77)
      expect(mmu.instance_variable_get(:@io)[APU::REGISTERS[:nr50] - MMU::IO_RANGE_BEGIN]).to eq(0)
    end

    it 'keeps storing non-APU IO registers itself' do
      mmu.write(0xFF01, 0x01) # serial data, not an APU register

      expect(mmu.instance_variable_get(:@io)[0xFF01 - MMU::IO_RANGE_BEGIN]).to eq(0x01)
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
      dma_ppu = build_ppu(m)
      m.write(MMU::ADDR_DMA, 0x01) # source = 0x0100 (ROM)
      expect(dma_ppu.oam_reader.read_oams[0]).to eq(0xAA)
    end

    it 'does not trigger DMA when writing 0 to ADDR_DMA (matches existing behavior)' do
      rom = build_rom(bytes: [0xAA])
      m = build_mmu(rom:)
      dma_ppu = build_ppu(m)
      m.write(MMU::ADDR_DMA, 0x00)
      expect(dma_ppu.oam_reader.read_oams[0]).to eq(0xFF) # untouched, DMA did not run
    end

    it 'arms the speed shifter when bit 0 of KEY1 (0xFF4D) is set, in CGB mode' do
      m = build_mmu(cgb: :only)
      m.write(0xFF4D, 0x01)
      expect(m.speed_shift.armed).to eq(true)
    end

    it 'does not arm the speed shifter when bit 0 of KEY1 is clear, in CGB mode' do
      m = build_mmu(cgb: :only)
      m.write(0xFF4D, 0x80)
      expect(m.speed_shift.armed).to eq(false)
    end

    it 'never arms the speed shifter outside CGB mode, even with bit 0 set' do
      mmu.write(0xFF4D, 0x01)
      expect(mmu.speed_shift.armed).to eq(false)
    end

    CGB_PLACEHOLDER_ADDRESSES.each do |addr|
      it "does not raise writing #{format('0x%04X', addr)}, in DMG mode" do
        expect { mmu.write(addr, 0xFF) }.not_to raise_error
      end

      it "does not raise writing #{format('0x%04X', addr)}, in CGB mode" do
        m = build_mmu(cgb: :only)
        expect { m.write(addr, 0xFF) }.not_to raise_error
      end
    end

    it 'routes BCPS/BCPD (0xFF68/69) to the PPU BG palette, in CGB mode' do
      m = build_mmu(cgb: :only)
      ppu = build_ppu(m)
      m.write(0xFF68, 0x80) # index 0, auto-increment
      m.write(0xFF69, 0x1F) # low byte: max red
      m.write(0xFF69, 0x00) # high byte

      expect(ppu.bg_palette.color(palette: 0, index: 0)).to eq(Screen.pack_color(0xFF, 0x00, 0x00, 0xFF))
    end

    it 'routes OCPS/OCPD (0xFF6A/6B) to the PPU OBJ palette, independently from BG' do
      m = build_mmu(cgb: :only)
      ppu = build_ppu(m)
      m.write(0xFF6A, 0x80)
      m.write(0xFF6B, 0x00)
      m.write(0xFF6B, 0x7C) # high byte: max blue

      expect(ppu.obj_palette.color(palette: 0, index: 0)).to eq(Screen.pack_color(0x00, 0x00, 0xFF, 0xFF))
      expect(ppu.bg_palette.color(palette: 0, index: 0)).to eq(Screen.pack_color(0xFF, 0xFF, 0xFF, 0xFF)) # untouched
    end

    it 'does not write to the palette RAM outside CGB mode' do
      ppu = build_ppu(mmu)
      mmu.write(0xFF68, 0x80)
      mmu.write(0xFF69, 0x1F)

      expect(ppu.bg_palette.color(palette: 0, index: 0)).to eq(Screen.pack_color(0xFF, 0xFF, 0xFF, 0xFF)) # untouched, still white
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

  describe 'boot_io' do
    it 'seeds the timer registers, not just the plain I/O ones' do
      m = build_mmu(boot_io: BootValues::DMG_IO_ROM_BOOT_VALUES.dup)

      expect(m.read(0xFF04)).to eq(0xAB) # DIV
      expect(m.read(0xFF07)).to eq(0xF8) # TAC
    end
  end
end
