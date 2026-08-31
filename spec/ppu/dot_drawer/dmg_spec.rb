# frozen_string_literal: true

require_relative '../../../lib/ppu'
require_relative '../../../lib/mmu'
require_relative '../../../lib/screen'

RSpec.describe PPU::DotDrawer::DMG do
  let(:mmu) { build_mmu }
  let!(:ppu) { build_ppu(mmu) }

  def write_uniform_tile(addr, color)
    byte1 = color.nobits?(0x01) ? 0x00 : 0xFF
    byte2 = color.nobits?(0x02) ? 0x00 : 0xFF
    16.times.each_slice(2) do |lo, hi|
      mmu.write(addr + lo, byte1)
      mmu.write(addr + hi, byte2)
    end
  end

  # 80 cycles to enter mode 3, +1 to draw screen_x=0
  def draw_first_pixel = ppu.tick(81)

  before do
    mmu.write(0x9800, 0x00) # bg map tile_x=0 -> tile index 0
    write_uniform_tile(0x8000, 2) # background tile -> color 2 everywhere
    mmu.write(0xFF47, 0xE4) # BGP: identity palette (0->0, 1->1, 2->2, 3->3)
  end

  it 'renders the background normally when LCDC.0 (BG/window enable) is set' do
    mmu.write(0xFF40, 0x91) # LCD on, BG enabled

    draw_first_pixel

    expect(ppu.framebuffer.get_pixel(0, 0)).to eq(PPU::DotDrawer::COLOR_RGBA_SDL[2])
  end

  it 'forces background color 0 when LCDC.0 is clear, ignoring the actual tile data' do
    mmu.write(0xFF40, 0x90) # LCD on, BG/window disabled (bit 0 clear)

    draw_first_pixel

    expect(ppu.framebuffer.get_pixel(0, 0)).to eq(PPU::DotDrawer::COLOR_RGBA_SDL[0])
  end

  it 'still shows a sprite over the forced-blank background when LCDC.0 is clear' do
    mmu.write(0xFF40, 0x92) # LCD on, BG/window disabled, OBJ enabled
    mmu.write(0xFF48, 0xE4) # OBP0: identity palette
    write_uniform_tile(0x8010, 1) # sprite tile -> color 1
    mmu.write(0xFE00, 16) # sprite Y (screen row 0)
    mmu.write(0xFE01, 8)  # sprite X (screen col 0)
    mmu.write(0xFE02, 1)  # tile index
    mmu.write(0xFE03, 0x00) # attributes: OBP0, no flip, priority 0

    draw_first_pixel

    expect(ppu.framebuffer.get_pixel(0, 0)).to eq(PPU::DotDrawer::COLOR_RGBA_SDL[1])
  end
end
