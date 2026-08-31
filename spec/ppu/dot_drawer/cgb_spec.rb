# frozen_string_literal: true

require_relative '../../../lib/ppu'
require_relative '../../../lib/mmu'
require_relative '../../../lib/screen'

RSpec.describe PPU::DotDrawer::CGB do
  let(:mmu) { build_mmu(cgb: :only) }
  let!(:ppu) { build_ppu(mmu) }

  subject(:dot_drawer) { ppu.dot_drawer }

  def write_vram(addr, value, bank: 0)
    mmu.write(0xFF4F, bank) # VBK
    mmu.write(addr, value)
    mmu.write(0xFF4F, 0)
  end

  def write_uniform_tile(addr, color, bank: 0)
    byte1 = color.nobits?(0x01) ? 0x00 : 0xFF
    byte2 = color.nobits?(0x02) ? 0x00 : 0xFF
    16.times.each_slice(2) do |lo, hi|
      write_vram(addr + lo, byte1, bank:)
      write_vram(addr + hi, byte2, bank:)
    end
  end

  # index/color: BCPS/BCPD auto-increment from the given byte offset (palette*8 + color*2).
  def write_cgb_color(palette:, color:, r5:, g5:, b5:)
    offset = (palette * 8) + (color * 2)
    rgb555 = r5 | (g5 << 5) | (b5 << 10)
    mmu.write(0xFF68, 0x80 | offset) # BCPS: auto-increment on
    mmu.write(0xFF69, rgb555 & 0xFF)
    mmu.write(0xFF69, (rgb555 >> 8) & 0xFF)
  end

  before do
    mmu.write(0xFF40, 0x91) # LCD on, unsigned tile addressing, bg tile map 0x9800, obj off
    mmu.write(0x9800, 0x00) # bg map tile_x=0 -> tile index 0
  end

  # 80 cycles to enter mode 3, +1 to draw screen_x=0
  def draw_first_pixel = ppu.tick(81)

  it 'resolves the background color through the CGB palette named by the tile attribute' do
    write_uniform_tile(0x8000, 1) # tile color index 1
    write_vram(0x9800, 0x05, bank: 1) # attribute: palette 5, no flip, bank 0
    write_cgb_color(palette: 5, color: 1, r5: 0x1F, g5: 0x00, b5: 0x00) # pure red

    draw_first_pixel

    expect(ppu.framebuffer.get_pixel(0, 0)).to eq(Screen.pack_color(0xFF, 0x00, 0x00, 0xFF))
  end

  it 'fetches the tile bitmap from the VRAM bank named by attribute bit 3' do
    write_uniform_tile(0x8000, 0, bank: 0) # bank 0: transparent
    write_uniform_tile(0x8000, 1, bank: 1) # bank 1: color 1, completely different bitmap
    write_vram(0x9800, 0x08, bank: 1) # attribute bit 3 set -> fetch tile data from bank 1
    write_cgb_color(palette: 0, color: 1, r5: 0x00, g5: 0x1F, b5: 0x00) # pure green

    draw_first_pixel

    expect(ppu.framebuffer.get_pixel(0, 0)).to eq(Screen.pack_color(0x00, 0xFF, 0x00, 0xFF))
  end

  it 'mirrors the background tile horizontally when attribute bit 5 (X flip) is set' do
    # column 0 lit, rest transparent -- flipped, the lit pixel lands on column 7
    write_tile_low_high = lambda { |addr, byte1, byte2|
      8.times do |row|
        write_vram(addr + (row * 2), byte1)
        write_vram(addr + (row * 2) + 1, byte2)
      end
    }
    write_tile_low_high.call(0x8000, 0x80, 0x00) # column 0 = color 1
    write_vram(0x9800, 0x20, bank: 1) # bit 5 = X flip
    write_cgb_color(palette: 0, color: 0, r5: 0x00, g5: 0x00, b5: 0x00) # black, distinct from CGBPalette's default white
    write_cgb_color(palette: 0, color: 1, r5: 0x1F, g5: 0x1F, b5: 0x1F) # white

    ppu.tick(80 + 8) # 7 pixels in, to reach column 7

    expect(ppu.framebuffer.get_pixel(7, 0)).to eq(Screen.pack_color(0xFF, 0xFF, 0xFF, 0xFF)) # tile column 0 (lit) shown here
    expect(ppu.framebuffer.get_pixel(0, 0)).to eq(Screen.pack_color(0x00, 0x00, 0x00, 0xFF)) # tile column 7 (transparent) here
  end

  it 'mirrors the background tile vertically when attribute bit 6 (Y flip) is set' do
    # row 0 lit (color 1), row 7 transparent (color 0) -- flipped, row 0 on screen shows row 7's data
    rows = Array.new(8) { |i| i.zero? ? [0xFF, 0x00] : [0x00, 0x00] }
    rows.each_with_index do |(b1, b2), i|
      write_vram(0x8000 + (i * 2), b1)
      write_vram(0x8000 + (i * 2) + 1, b2)
    end
    write_vram(0x9800, 0x40, bank: 1) # bit 6 = Y flip
    write_cgb_color(palette: 0, color: 0, r5: 0x1F, g5: 0x00, b5: 0x1F) # color 0 != default black, so the flip is observable

    draw_first_pixel

    expect(ppu.framebuffer.get_pixel(0, 0)).to eq(Screen.pack_color(0xFF, 0x00, 0xFF, 0xFF)) # row 7 (transparent/color 0) shown
  end
end
