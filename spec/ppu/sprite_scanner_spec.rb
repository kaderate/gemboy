# frozen_string_literal: true

require_relative '../../lib/ppu'
require_relative '../../lib/mmu'

RSpec.describe PPU::SpriteScanner do
  subject(:scanner) { described_class.new(mmu:, vram: ppu.vram, oam_reader: ppu.oam_reader) }

  let!(:mmu) { build_mmu }
  let!(:ppu) { build_ppu(mmu) }

  # Row with a single lit pixel (color 1) at the given column, transparent (color 0) elsewhere.
  def pixel_row(column) = [0x80 >> column, 0x00]

  def write_tile_rows(addr, rows)
    rows.each_with_index do |(byte1, byte2), i|
      mmu.write(addr + (i * 2), byte1)
      mmu.write(addr + (i * 2) + 1, byte2)
    end
  end

  def write_uniform_tile(addr, row = pixel_row(0)) = write_tile_rows(addr, Array.new(8, row))

  def write_oam_sprite(index, y:, x:, tile_index: 0, attributes: 0x00)
    base = 0xFE00 + (index * 4)
    mmu.write(base, y)
    mmu.write(base + 1, x)
    mmu.write(base + 2, tile_index)
    mmu.write(base + 3, attributes)
  end

  def scanline_at(y, obj_size: false)
    PPU::Scanline.new(ppu: nil).tap do |s|
      s.value = y
      s.obj_size = obj_size
      s.sprite_data_addr = 0x8000
    end
  end

  def sprites_at(y, obj_size: false)
    scanline_at(y, obj_size:).tap { scanner.scan_and_cache(scanline: _1, obj_display_enable: true) }.oam_sprites
  end

  before { write_uniform_tile(0x8000) }

  it 'ignores sprites outside the current scanline' do
    write_oam_sprite(0, y: 16, x: 8) # covers screen rows 0..7

    scanner.scan_and_cache(scanline: scanline_at(8), obj_display_enable: true)

    expect(scanner.sprite_pixel_cache.compact).to be_empty
  end

  it 'clears the previous selection and cache when obj display is disabled' do
    write_oam_sprite(0, y: 16, x: 8)

    scanline = scanline_at(0)
    scanner.scan_and_cache(scanline:, obj_display_enable: false)

    expect(scanner.sprite_pixel_cache.compact).to be_empty
    expect(scanline.oam_sprites).to eq([])
  end

  it 'caps selection at 10 sprites per scanline' do
    11.times { |i| write_oam_sprite(i, y: 16, x: 8 + i) }

    scanline = scanline_at(0)
    scanner.scan_and_cache(scanline:, obj_display_enable: true)

    expect(scanline.oam_sprites.size).to eq(10)
  end

  it 'keeps the first ten sprites in OAM order, not the ten leftmost' do
    12.times { |i| write_oam_sprite(i, y: 16, x: 100 - i) } # decreasing X: OAM order and X order disagree

    scanline = scanline_at(0)
    scanner.scan_and_cache(scanline:, obj_display_enable: true)

    expect(scanline.oam_sprites.map { _1[:oam_index] }).to eq((0..9).to_a)
  end

  # The scan must reach OAM slot 39: an off-by-one on the loop bound silently drops the last sprite.
  it 'scans the whole OAM, down to the last slot' do
    write_oam_sprite(39, y: 16, x: 8)

    scanline = scanline_at(0)
    scanner.scan_and_cache(scanline:, obj_display_enable: true)

    expect(scanline.oam_sprites.map { _1[:oam_index] }).to eq([39])
  end

  it 'reports the OAM index and the screen X of each selected sprite' do
    write_oam_sprite(2, y: 16, x: 24)
    write_oam_sprite(5, y: 16, x: 8)

    scanline = scanline_at(0)
    scanner.scan_and_cache(scanline:, obj_display_enable: true)

    expect(scanline.oam_sprites.map { [_1[:oam_index], _1[:x]] }).to eq([[2, 16], [5, 0]])
  end

  it 'hands each selected sprite its own four OAM bytes' do
    write_oam_sprite(3, y: 16, x: 8, tile_index: 0x12, attributes: 0x60)

    scanline = scanline_at(0)
    scanner.scan_and_cache(scanline:, obj_display_enable: true)

    expect(scanline.oam_sprites.first[:oam_memory]).to eq([16, 8, 0x12, 0x60])
  end

  it 'selects on Y alone, including a sprite pushed entirely off the left edge' do
    write_oam_sprite(0, y: 16, x: 0) # screen X = -8, no visible pixel

    scanline = scanline_at(0)
    scanner.scan_and_cache(scanline:, obj_display_enable: true)

    expect(scanline.oam_sprites.map { _1[:x] }).to eq([-8])
    expect(scanner.sprite_pixel_cache.compact).to be_empty
  end

  [[false, 8], [true, 16]].each do |obj_size, height|
    it "covers exactly #{height} rows in 8x#{height} mode" do
      write_oam_sprite(0, y: 16, x: 8) # covers screen rows 0..#{height - 1}

      expect(sprites_at(0, obj_size:).size).to eq(1)
      expect(sprites_at(height - 1, obj_size:).size).to eq(1)
      expect(sprites_at(height, obj_size:)).to be_empty
    end
  end

  it 'breaks priority ties on OAM index when two sprites share the same X' do
    write_uniform_tile(0x8010, pixel_row(0)) # tile 1, also lit at column 0
    write_oam_sprite(0, y: 16, x: 8, tile_index: 0) # lower OAM index
    write_oam_sprite(1, y: 16, x: 8, tile_index: 1) # same X, higher index

    scanner.scan_and_cache(scanline: scanline_at(0), obj_display_enable: true)

    expect(scanner.sprite_pixel_cache[0]).to eq([1, 0, 0]) # sprite 0 drawn first, sprite 1 never overwrites it
  end

  it 'flips the tile vertically when the Y-flip attribute bit is set' do
    write_tile_rows(0x8000, [pixel_row(0)] + Array.new(6) { [0x00, 0x00] } + [pixel_row(7)])
    write_oam_sprite(0, y: 16, x: 8, attributes: 0x40) # bit6 = Y flip

    scanner.scan_and_cache(scanline: scanline_at(0), obj_display_enable: true)

    expect(scanner.sprite_pixel_cache[7]).to eq([1, 0, 0]) # row 0 requested, row 7's content shown
    expect(scanner.sprite_pixel_cache[0]).to be_nil
  end

  it 'masks tile index bit 0 and doubles the tile height in 8x16 mode' do
    write_uniform_tile(0x8000, pixel_row(0)) # top tile (even index)
    write_uniform_tile(0x8010, pixel_row(3)) # bottom tile (tile_index 1, odd -- must be masked off)
    write_oam_sprite(0, y: 16, x: 8, tile_index: 1)

    scanner.scan_and_cache(scanline: scanline_at(8, obj_size: true), obj_display_enable: true) # second row of the sprite

    expect(scanner.sprite_pixel_cache[3]).to eq([1, 0, 0])
  end

  it 'reuses the decoded tile across calls until clear_cache is called' do
    write_oam_sprite(0, y: 16, x: 8)
    scanner.scan_and_cache(scanline: scanline_at(0), obj_display_enable: true)
    expect(scanner.sprite_pixel_cache[0]).to eq([1, 0, 0])

    # Overwrite VRAM with a fully transparent tile at the same address -- without cache invalidation,
    # the stale decoded Tile keeps reporting the old color.
    write_uniform_tile(0x8000, [0x00, 0x00])
    scanner.scan_and_cache(scanline: scanline_at(0), obj_display_enable: true)
    expect(scanner.sprite_pixel_cache[0]).to eq([1, 0, 0]) # still stale

    scanner.clear_cache
    scanner.scan_and_cache(scanline: scanline_at(0), obj_display_enable: true)
    expect(scanner.sprite_pixel_cache[0]).to be_nil # re-decoded from the now-transparent VRAM
  end
end
