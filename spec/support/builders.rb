# frozen_string_literal: true

require_relative '../../lib/mbc'
require_relative '../../lib/mmu'
require_relative '../../lib/cpu'
require_relative '../../lib/ppu'
require_relative '../../lib/cartridge_loader'

module Builders
  DEFAULT_ROM_BANK_COUNT = 2
  ENTRY_POINT = 0x100

  def build_rom(bank_count: DEFAULT_ROM_BANK_COUNT, bytes: [], at: 0)
    rom = Array.new(bank_count * MBC::Constants::ROM_BANK_SIZE, 0x00)
    bytes.each_with_index { |byte, i| rom[at + i] = byte }
    rom
  end

  # The per-bank marker tells which bank got mapped onto a given window.
  def build_marked_rom(bank_count:)
    build_rom(bank_count:).tap do |rom|
      bank_count.times do |bank|
        base = bank * MBC::Constants::ROM_BANK_SIZE
        rom[base] = bank & 0xFF
        rom[base + 1] = (bank >> 8) & 0xFF
      end
    end
  end

  def build_cartridge(rom: nil, mbc: 0, rom_bank_count: nil, ram_bank_count: 0, with_battery: false,
                      with_timer: false, rom_path: 'spec/fixture.gb')
    rom ||= build_rom
    rom_bank_count ||= rom.size / MBC::Constants::ROM_BANK_SIZE
    cartridge_config = CartridgeLoader::CartridgeConfig.new(mbc:, rom_declared_size: rom.size, rom_bank_count:,
                                                            ram_bank_count:, with_battery:, with_timer:)
    CartridgeLoader::Cartridge.new(rom_path:, name: 'SPEC', rom_bytes: rom, cartridge_config:)
  end

  def build_mbc(**cartridge_options)
    MBC.build(build_cartridge(**cartridge_options))
  end

  def build_external_ram(bank_count: 1, battery_path: nil, enabled: true)
    MBC::ExternalRAM.new(bank_count:, battery_path:).tap { _1.enabled = enabled }
  end

  def build_mmu(debug_config: {}, boot_io: nil, **cartridge_options)
    MMU.new(mbc: build_mbc(**cartridge_options), debug_config:).tap do |mmu|
      mmu.initialize_io(boot_io) if boot_io
    end
  end

  def build_cpu(*bytes, at: ENTRY_POINT, **mmu_options)
    CPU.new(build_mmu(rom: build_rom(bytes:, at:), **mmu_options), logger: nil)
  end

  def build_ppu(mmu = build_mmu)
    PPU.new(mmu).tap { mmu.attach_ppu(_1) }
  end
end
