# frozen_string_literal: true

require_relative '../../../lib/debug/probes/ppu_probe'

RSpec.describe Debug::Probes::PPUProbe do
  let(:mmu) { build_mmu }
  let(:ppu) { build_ppu(mmu) }

  subject(:probe) { described_class.new(ppu:, mmu:) }

  it 'decode une tuile en indices de palette' do
    # Ligne 0 : low = 0b10000001, high = 0b01000001. Chaque pixel vaut (bit_high << 1) | bit_low,
    # du bit 7 (colonne 0) au bit 0 (colonne 7).
    mmu.write(0x8000, 0b1000_0001)
    mmu.write(0x8001, 0b0100_0001)

    expect(probe.snapshot[:tiles][0][0, 8]).to eq([1, 2, 0, 0, 0, 0, 0, 3])
  end

  it 'expose les 384 tuiles de 64 pixels' do
    tiles = probe.snapshot[:tiles]
    expect(tiles.size).to eq(384)
    expect(tiles.map(&:size).uniq).to eq([64])
  end

  it 'expose les deux tilemaps dans l ordre 0x9800 puis 0x9C00' do
    mmu.write(0x9800, 0x11)
    mmu.write(0x9C00, 0x22)

    tilemaps = probe.snapshot[:tilemaps]
    expect(tilemaps.map(&:size)).to eq([1024, 1024])
    expect([tilemaps[0][0], tilemaps[1][0]]).to eq([0x11, 0x22])
  end

  it 'expose les 40 entrees OAM decodees' do
    mmu.write(0xFE00, 0x10)
    mmu.write(0xFE01, 0x20)
    mmu.write(0xFE02, 0x30)
    mmu.write(0xFE03, 0x40)

    oam = probe.snapshot[:oam]
    expect(oam.size).to eq(40)
    expect(oam[0]).to eq(y: 0x10, x: 0x20, tile: 0x30, flags: 0x40)
  end

  it 'expose les registres bruts' do
    mmu.write(MMU::ADDR_SCX, 0x07)
    mmu.write(MMU::ADDR_BGP, 0xE4)

    registers = probe.snapshot[:registers]
    expect(registers[:scx]).to eq(0x07)
    expect(registers[:bgp]).to eq(0xE4)
  end

  it 'lit la VRAM meme quand le PPU la verrouille' do
    mmu.write(0x8000, 0xFF)
    mmu.set_accessible_memory(oam: false, vram: false)

    expect(probe.snapshot[:tiles][0][0, 8]).to eq([1, 1, 1, 1, 1, 1, 1, 1])
  end

  it 'expose le mode courant du PPU et la version VRAM' do
    snapshot = probe.snapshot
    expect(snapshot[:mode]).to eq(ppu.mode)
    expect(snapshot[:vram_version]).to eq(mmu.vram_version)
  end
end
