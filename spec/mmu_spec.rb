require_relative '../lib/mmu'
require_relative '../lib/key_state'

RSpec.describe MMU do
  def make_mmu
    described_class.new(Array.new(0x8000, 0x00))
  end

  # --- read: direct semantic checks against the known GameBoy memory map ---
  describe '#read' do
    subject(:mmu) { make_mmu }

    it 'reads ROM bytes directly' do
      rom = Array.new(0x8000, 0x00)
      rom[0x0000] = 0xAB
      rom[0x7FFF] = 0xCD
      m = described_class.new(rom)
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
    subject(:mmu) { make_mmu }

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
      rom = Array.new(0x8000, 0x00)
      rom[0x0100] = 0xAA
      m = described_class.new(rom)
      m.write(MMU::ADDR_DMA, 0x01) # source = 0x0100 (ROM)
      expect(m.read_oams[0]).to eq(0xAA)
    end

    it 'does not trigger DMA when writing 0 to ADDR_DMA (matches existing behavior)' do
      rom = Array.new(0x8000, 0x00)
      rom[0x0000] = 0xAA
      m = described_class.new(rom)
      m.write(MMU::ADDR_DMA, 0x00)
      expect(m.read_oams[0]).to eq(0xFF) # untouched, DMA did not run
    end
  end

  describe 'serial transfer (debug_config[:mmu_serial])' do
    it 'completes the transfer instantly and records the byte when enabled' do
      m = described_class.new(Array.new(0x8000, 0x00), debug_config: { mmu_serial: true })
      m.write(MMU::ADDR_SB, 'A'.ord)
      m.write(MMU::ADDR_SC, 0x81) # bit 7 = transfer start, bit 0 = internal clock

      expect(m.serial_output).to eq('A')
      expect(m.read(MMU::ADDR_SC) & 0x80).to eq(0) # bit 7 cleared: transfer "done"
    end

    it 'does nothing special when disabled (default behavior)' do
      m = described_class.new(Array.new(0x8000, 0x00))
      m.write(MMU::ADDR_SB, 'A'.ord)
      m.write(MMU::ADDR_SC, 0x81)

      expect(m.serial_output).to be_nil
      expect(m.read(MMU::ADDR_SC) & 0x80).not_to eq(0) # bit 7 left untouched
    end
  end

  describe 'MBC1 banking' do
    ROM_BANKS = 128 # 2MB (max MBC1) : évite tout wrap via `% rom_bank_count` sur les banques hautes
    RAM_BANKS = 4 # 32KB

    # Chaque banque ROM commence par un octet marqueur = son propre index, pour identifier
    # sans ambiguïté quelle banque a été mappée sur la fenêtre 0x4000-0x7FFF.
    def make_mbc1_mmu(rom_bank_count: ROM_BANKS, ram_bank_count: RAM_BANKS)
      rom = Array.new(rom_bank_count * RomLoader::ROM_BANK_SIZE, 0x00)
      rom_bank_count.times { |bank| rom[bank * RomLoader::ROM_BANK_SIZE] = bank }

      cartridge_config = RomLoader::CartridgeConfig.new(mbc: 1, rom_declared_size: rom.size,
                                                        rom_bank_count:, ram_bank_count:)
      described_class.new(rom, cartridge_config:)
    end

    def enable_ram(mmu)
      mmu.write(0x0000, 0x0A)
    end

    describe 'ROM bank select (0x2000-0x3FFF, 5 bits)' do
      subject(:mmu) { make_mbc1_mmu }

      it 'selects the given bank for the 0x4000-0x7FFF window' do
        mmu.write(0x2000, 5)
        expect(mmu.read(0x4000)).to eq(5)
      end

      it 'maps bank 0 to bank 1 (hardware quirk)' do
        mmu.write(0x2000, 0)
        expect(mmu.read(0x4000)).to eq(1)
      end

      it 'masks to 5 bits' do
        mmu.write(0x2000, 0b1110_0011) # garde seulement 0b00011 = 3
        expect(mmu.read(0x4000)).to eq(3)
      end
    end

    describe 'secondary bank register (0x4000-0x5FFF, bits 5-6)' do
      subject(:mmu) { make_mbc1_mmu }

      it 'extends the ROM bank for 0x4000-0x7FFF regardless of the banking mode (mode 0, default)' do
        mmu.write(0x2000, 1)  # 5 bits bas = 1
        mmu.write(0x4000, 1)  # registre secondaire = 1 -> bit 5

        expect(mmu.read(0x4000)).to eq(0b0100001) # 33
      end

      it 'still extends the ROM bank for 0x4000-0x7FFF in mode 1' do
        mmu.write(0x6000, 1) # mode 1
        mmu.write(0x2000, 1)
        mmu.write(0x4000, 1)

        expect(mmu.read(0x4000)).to eq(0b0100001) # 33
      end

      it 'masks to 2 bits' do
        mmu.write(0x2000, 1)
        mmu.write(0x4000, 0b1111_1110) # garde seulement 0b10 = 2

        expect(mmu.read(0x4000)).to eq(0b1000001) # 65
      end
    end

    describe 'banking mode (0x6000-0x7FFF) and the fixed 0x0000-0x3FFF window' do
      subject(:mmu) { make_mbc1_mmu }

      it 'keeps 0x0000-0x3FFF fixed on bank 0 in mode 0 (default), even with the secondary register set' do
        mmu.write(0x4000, 1)
        expect(mmu.read(0x0000)).to eq(0)
      end

      it 'applies the secondary register to 0x0000-0x3FFF in mode 1' do
        mmu.write(0x6000, 1) # mode 1
        mmu.write(0x4000, 1) # secondaire = 1 -> banque 32 pour la fenêtre basse

        expect(mmu.read(0x0000)).to eq(32)
      end
    end

    describe 'external RAM banking' do
      subject(:mmu) { make_mbc1_mmu }

      it 'returns 0xFF when RAM is not enabled' do
        mmu.write(0xA000, 0x42) # ignoré, RAM désactivée
        expect(mmu.read(0xA000)).to eq(0xFF)
      end

      it 'reads/writes bank 0 by default (mode 0)' do
        enable_ram(mmu)
        mmu.write(0xA000, 0x42)
        expect(mmu.read(0xA000)).to eq(0x42)
      end

      it 'stays on RAM bank 0 in mode 0 even if the secondary register is set' do
        enable_ram(mmu)
        mmu.write(0xA000, 0x11)
        mmu.write(0x4000, 2) # ignoré en mode 0 pour la RAM

        expect(mmu.read(0xA000)).to eq(0x11)
      end

      it 'switches RAM bank in mode 1, keeping banks independent' do
        mmu.write(0x6000, 1) # mode 1
        enable_ram(mmu)

        mmu.write(0x4000, 0) # banque RAM 0
        mmu.write(0xA000, 0xAA)

        mmu.write(0x4000, 2) # banque RAM 2
        mmu.write(0xA000, 0xBB)

        mmu.write(0x4000, 0)
        expect(mmu.read(0xA000)).to eq(0xAA) # toujours là, pas écrasé par la banque 2

        mmu.write(0x4000, 2)
        expect(mmu.read(0xA000)).to eq(0xBB)
      end
    end
  end

  describe 'MBC5 banking' do
    ROM_BANKS_MBC5 = 512 # 8MB (max MBC5) : couvre les 9 bits du registre de banque ROM

    def make_mbc5_mmu(rom_bank_count: ROM_BANKS_MBC5, ram_bank_count: 4)
      rom = Array.new(rom_bank_count * RomLoader::ROM_BANK_SIZE, 0x00)
      rom_bank_count.times do |bank|
        rom[bank * RomLoader::ROM_BANK_SIZE] = bank & 0xFF
        rom[(bank * RomLoader::ROM_BANK_SIZE) + 1] = (bank >> 8) & 0xFF
      end

      cartridge_config = RomLoader::CartridgeConfig.new(mbc: 5, rom_declared_size: rom.size,
                                                        rom_bank_count:, ram_bank_count:)
      described_class.new(rom, cartridge_config:)
    end

    it 'selects a ROM bank via the low byte (0x2000-0x2FFF)' do
      mmu = make_mbc5_mmu
      mmu.write(0x2000, 5)
      expect(mmu.read(0x4000)).to eq(5)
    end

    it 'allows selecting bank 0 for the switchable window (no MBC1-style quirk)' do
      mmu = make_mbc5_mmu
      mmu.write(0x2000, 1)
      mmu.write(0x2000, 0)
      expect(mmu.read(0x4000)).to eq(0)
    end

    it 'combines the low byte and the high bit (0x3000-0x3FFF) into a 9-bit bank number' do
      mmu = make_mbc5_mmu
      mmu.write(0x2000, 0x34)
      mmu.write(0x3000, 1)
      bank = mmu.read(0x4000) | (mmu.read(0x4001) << 8)
      expect(bank).to eq(0x134)
    end

    it 'switches RAM bank via the 4-bit register (0x4000-0x5FFF), independently of any mode' do
      mmu = make_mbc5_mmu
      mmu.write(0x0000, 0x0A) # RAM enable

      mmu.write(0x4000, 0)
      mmu.write(0xA000, 0xAA)

      mmu.write(0x4000, 2)
      mmu.write(0xA000, 0xBB)

      mmu.write(0x4000, 0)
      expect(mmu.read(0xA000)).to eq(0xAA)

      mmu.write(0x4000, 2)
      expect(mmu.read(0xA000)).to eq(0xBB)
    end
  end

  describe 'external RAM on cartridges without any MBC (cart_type 0x08/0x09, ROM+RAM)' do
    def make_no_mbc_mmu(ram_bank_count:)
      rom = Array.new(0x8000, 0x00)
      cartridge_config = RomLoader::CartridgeConfig.new(mbc: 0, rom_declared_size: rom.size, rom_bank_count: 2,
                                                        ram_bank_count:)
      described_class.new(rom, cartridge_config:)
    end

    it 'is accessible without any enable sequence when the cartridge has RAM' do
      mmu = make_no_mbc_mmu(ram_bank_count: 1)
      mmu.write(0xA000, 0x42)
      expect(mmu.read(0xA000)).to eq(0x42)
    end

    it 'stays at 0xFF when the cartridge declares no RAM at all' do
      mmu = make_no_mbc_mmu(ram_bank_count: 0)
      mmu.write(0xA000, 0x42)
      expect(mmu.read(0xA000)).to eq(0xFF)
    end
  end
end
