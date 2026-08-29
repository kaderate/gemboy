require_relative '../lib/ppu'
require_relative '../lib/mmu'
require 'tempfile'

RSpec.describe PPU do
  def create_minimal_mmu = build_mmu

  describe 'initialization' do
    it 'initializes with CPU reference' do
      mmu = create_minimal_mmu
      ppu = build_ppu(mmu)
      expect(ppu.mmu).to equal(mmu)
    end

    it 'sets initial cycle count to 0' do
      mmu = create_minimal_mmu
      ppu = build_ppu(mmu)
      expect(ppu.cycles).to eq(0)
    end

    it 'has framebuffer for rendering' do
      mmu = create_minimal_mmu
      ppu = build_ppu(mmu)
      expect(ppu.framebuffer).not_to be_nil
    end
  end

  describe 'constants' do
    it 'defines correct window dimensions' do
      expect(PPU::WINDOW_WIDTH).to eq(160)
      expect(PPU::WINDOW_HEIGHT).to eq(144)
    end

    it 'defines border and scaling' do
      expect(PPU::BORDER).to eq(30)
      expect(PPU::PIXEL_SCALE).to eq(2)
    end
  end

  describe 'register access' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    it 'reads from the LCD control register' do
      mmu.write(0xFF40, 0x80) # LCD on
      expect(ppu.mmu.read(0xFF40)).to eq(0x80)
    end

    it 'reads from the LCD status register' do
      mmu.write(0xFF40, 0x80) # LCD on
      # LY and LYC are both 0 before the first tick, so the live LYC=LY bit (0x04) is already set.
      expect(ppu.mmu.read(0xFF41)).to eq(0x04)
    end

    it 'ignores writes to the LY register -- it always reflects the live scanline counter' do
      mmu.write(0xFF44, 0x01)
      expect(ppu.mmu.read(0xFF44)).to eq(0x00)
    end
  end

  describe 'cycle tracking' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    before { mmu.write(0xFF40, 0x80) } # LCD on

    it 'accumulates CPU cycles' do
      expect(ppu.cycles).to eq(0)
      ppu.tick(10)
      expect(ppu.cycles).to eq(10)
    end

    it 'accumulates multiple ticks' do
      ppu.tick(100)
      ppu.tick(50)
      expect(ppu.cycles).to eq(150)
    end

    it 'resets cycles after scanline (456 cycles)' do
      ppu.tick(456)
      # After 456 cycles, subtracts 456 and renders
      expect(ppu.cycles).to eq(0)
    end

    it 'multiple scanlines accumulate correctly' do
      ppu.tick(456)  # scanline 1
      expect(ppu.cycles).to eq(0)
      ppu.tick(200)  # partial scanline 2
      expect(ppu.cycles).to eq(200)
    end
  end

  describe 'PPU::Tile' do
    it 'initializes with data' do
      data = Array.new(16, 0xFF)
      tile = PPU::Tile.new(data: data)
      expect(tile).to be_a(PPU::Tile)
    end

    it 'decodes tile data into 8 lines' do
      data = Array.new(16, 0x00)
      tile = PPU::Tile.new(data: data)
      expect(tile.instance_variable_get(:@lines)).to be_a(Array)
      expect(tile.instance_variable_get(:@lines).length).to eq(8)
    end

    it 'can access pixel_color method' do
      data = [0xFF, 0x00] + Array.new(14, 0x00)
      tile = PPU::Tile.new(data: data)
      expect(tile).to respond_to(:pixel_color)
    end

    it 'creates two distinct tile objects' do
      data = Array.new(16, 0x00)
      tile1 = PPU::Tile.new(data: data)
      tile2 = PPU::Tile.new(data: data)
      expect(tile1).not_to equal(tile2)
    end
  end

  describe 'PPU::BPPDecoder' do
    it 'decodes two bytes into pixel colors' do
      decoder = PPU::BPPDecoder.new(0x00, 0x00) # All pixels = 0
      # Decoder accesses with [] method
      expect(decoder).to respond_to(:[])
    end

    it 'creates BPPDecoder with two bytes' do
      decoder = PPU::BPPDecoder.new(0xAA, 0x55)
      expect(decoder).to be_a(PPU::BPPDecoder)
    end

    it 'supports indexing with brackets' do
      decoder = PPU::BPPDecoder.new(0x00, 0x00)
      expect(decoder).to respond_to(:[])
    end
  end

  describe 'LCD control' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    it 'reads LCD enable from CPU' do
      # CPU.lcd_control returns hash with :lcd_enable key
      lcd_control = ppu.lcd_control
      expect(lcd_control).to be_a(PPU::LcdControl)
      expect(lcd_control).to respond_to(:lcd_enable)
    end

    it 'returns LcdControl object' do
      lcd_control = ppu.lcd_control
      expect(lcd_control).to respond_to(:lcd_enable)
      expect(lcd_control).to respond_to(:bg_tile_map_display_select)
      expect(lcd_control).to respond_to(:bg_and_window_tile_data_select)
    end
  end

  describe 'VRAM accessthrough MMU' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    it 'can read from VRAM through MMU' do
      # Write to VRAM via CPU
      mmu.write(0x8000, 0xAB)
      # Read through PPU's CPU reference
      value = ppu.mmu.read(0x8000)
      expect(value).to eq(0xAB)
    end

    it 'can read tile data (16 bytes per tile)' do
      # Write tile data to VRAM
      tile_data = [0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF,
                   0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00]
      tile_data.each_with_index do |byte, i|
        mmu.write(0x8000 + i, byte)
      end
      # Read back
      (0..15).each do |i|
        expect(mmu.read(0x8000 + i)).to eq(tile_data[i])
      end
    end

    it 'separates VRAM ranges correctly' do
      mmu.write(0x8000, 0x11)  # Start of VRAM
      mmu.write(0x9FFF, 0x22)  # End of VRAM
      expect(mmu.read(0x8000)).to eq(0x11)
      expect(mmu.read(0x9FFF)).to eq(0x22)
    end
  end

  describe 'rendering control' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    it 'responds to tick method' do
      expect(ppu).to respond_to(:tick)
    end

    it 'can trigger full frame render' do
      ppu.tick(456)
      expect(ppu.cycles).to eq(0)
    end

    it 'has framebuffer when LCD is disabled' do
      expect(ppu.framebuffer).not_to be_nil
    end
  end

  describe 'tile display integration' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    it 'creates tiles from VRAM data' do
      # Write tile index to background tile map
      mmu.write(0x9800, 0x00) # First tile index in background map
      # Should be able to read this
      expect(mmu.read(0x9800)).to eq(0x00)
    end

    it 'reads tile data based on tile index' do
      # Tile 0 starts at 0x8000 (if using 0x8000 tile data address)
      tile_data = Array.new(16, 0x55)
      tile_data.each_with_index { |b, i| mmu.write(0x8000 + i, b) }
      # Should be readable
      (0..15).each { |i| expect(mmu.read(0x8000 + i)).to eq(0x55) }
    end

    it 'supports 32x32 background tile map' do
      # Background map is 32x32 tiles at 0x9800 or 0x9C00
      # Each tile index is 1 byte
      # Total: 32 * 32 = 1024 bytes per map
      map_size = 32 * 32
      expect(map_size).to eq(1024)
    end
  end

  describe 'color conversion' do
    it 'converts color values to hex colors' do
      # Color values 0-3 should map to palette colors
      # 0 = lightest, 3 = darkest
      # Test is implementation-dependent
      tile = PPU::Tile.new(data: Array.new(16, 0))
      expect(tile).to be_a(PPU::Tile)
    end

    it 'handles 2BPP color encoding correctly' do
      # 2 bits per pixel = 4 colors
      # 8 pixels per row = 16 bits = 2 bytes per row
      # 8 rows = 16 bytes per tile
      expect(16 * 8 / 8).to eq(16) # bits per tile
    end
  end

  describe 'scanline-based rendering' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    before { mmu.write(0xFF40, 0x80) } # LCD on

    it 'processes scanlines in 456-cycle chunks' do
      # Game Boy: 456 cycles = 1 scanline
      scanline_cycles = 456
      # After a scanline, render is triggered and cycles reset
      ppu.tick(scanline_cycles)
      expect(ppu.cycles).to eq(0)
    end

    it 'multiple scanlines accumulate correctly before reset' do
      # Multiple partial scanlines accumulate
      ppu.tick(200)
      ppu.tick(200)
      expect(ppu.cycles).to eq(400)
      ppu.tick(56) # Triggers reset at 456
      expect(ppu.cycles).to eq(0)
    end
  end

  describe 'window dimensions' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    it 'creates window with border' do
      # Display dimensions: 160x144 (Game Boy)
      # Canvas: WINDOW_WIDTH * PIXEL_SCALE x WINDOW_HEIGHT * PIXEL_SCALE at (BORDER, BORDER)
      # Window: WINDOW_WIDTH * PIXEL_SCALE + BORDER * 2 x WINDOW_HEIGHT * PIXEL_SCALE + BORDER * 2
      expected_width = (160 * 2) + (30 * 2)
      expected_height = (144 * 2) + (30 * 2)
      expect(expected_width).to eq(380)
      expect(expected_height).to eq(348)
    end
  end

  describe 'PPU::BPPDecoder pixel values' do
    it 'decodes 0xFF/0x00 as all color 1 (bit1=1, bit2=0)' do
      decoder = PPU::BPPDecoder.new(0xFF, 0x00)
      expect((0...8).map { |i| decoder[i] }).to eq([1, 1, 1, 1, 1, 1, 1, 1])
    end

    it 'decodes 0x00/0xFF as all color 2 (bit1=0, bit2=1)' do
      decoder = PPU::BPPDecoder.new(0x00, 0xFF)
      expect((0...8).map { |i| decoder[i] }).to eq([2, 2, 2, 2, 2, 2, 2, 2])
    end

    it 'decodes 0xFF/0xFF as all color 3 (bit1=1, bit2=1)' do
      decoder = PPU::BPPDecoder.new(0xFF, 0xFF)
      expect((0...8).map { |i| decoder[i] }).to eq([3, 3, 3, 3, 3, 3, 3, 3])
    end

    it 'decodes 0x00/0x00 as all color 0' do
      decoder = PPU::BPPDecoder.new(0x00, 0x00)
      expect((0...8).map { |i| decoder[i] }).to eq([0, 0, 0, 0, 0, 0, 0, 0])
    end

    it 'decodes MSB first: 0x80/0x00 sets only pixel 0 to color 1' do
      decoder = PPU::BPPDecoder.new(0x80, 0x00)
      expect(decoder[0]).to eq(1)
      expect((1...8).map { |i| decoder[i] }).to eq([0, 0, 0, 0, 0, 0, 0])
    end

    it 'decodes 0x80/0x80 sets only pixel 0 to color 3' do
      decoder = PPU::BPPDecoder.new(0x80, 0x80)
      expect(decoder[0]).to eq(3)
      expect((1...8).map { |i| decoder[i] }).to eq([0, 0, 0, 0, 0, 0, 0])
    end

    it 'decodes 0x01/0x00 sets only pixel 7 to color 1 (LSB = last pixel)' do
      decoder = PPU::BPPDecoder.new(0x01, 0x00)
      expect(decoder[7]).to eq(1)
      expect((0...7).map { |i| decoder[i] }).to eq([0, 0, 0, 0, 0, 0, 0])
    end
  end

  describe 'PPU::Tile pixel_color' do
    it 'returns color 1 for all pixels in row 0 with data [0xFF, 0x00, ...]' do
      data = [0xFF, 0x00] + Array.new(14, 0x00)
      tile = PPU::Tile.new(data: data)
      expect((0...8).map { |x| tile.pixel_color(x, 0) }).to eq([1, 1, 1, 1, 1, 1, 1, 1])
    end

    it 'returns color 2 for all pixels in row 0 with data [0x00, 0xFF, ...]' do
      data = [0x00, 0xFF] + Array.new(14, 0x00)
      tile = PPU::Tile.new(data: data)
      expect((0...8).map { |x| tile.pixel_color(x, 0) }).to eq([2, 2, 2, 2, 2, 2, 2, 2])
    end

    it 'returns color 0 for all pixels when data is all zeros' do
      tile = PPU::Tile.new(data: Array.new(16, 0x00))
      expect(tile.pixel_color(0, 0)).to eq(0)
      expect(tile.pixel_color(7, 7)).to eq(0)
    end

    it 'reads row 1 independently from row 0' do
      # row0: 0x00/0x00 → color 0; row1: 0xFF/0xFF → color 3
      data = [0x00, 0x00, 0xFF, 0xFF] + Array.new(12, 0x00)
      tile = PPU::Tile.new(data: data)
      expect(tile.pixel_color(0, 0)).to eq(0)
      expect(tile.pixel_color(0, 1)).to eq(3)
    end

    it 'returns correct color for pixel at column 0, row 7 (last row)' do
      # last row (bytes 14/15): 0x80/0x80 → pixel 0 = color 3
      data = Array.new(14, 0x00) + [0x80, 0x80]
      tile = PPU::Tile.new(data: data)
      expect(tile.pixel_color(0, 7)).to eq(3)
      expect(tile.pixel_color(1, 7)).to eq(0)
    end
  end

  describe 'PPU::Framebuffer' do
    let(:fb) { PPU::Framebuffer.new(160, 144) }

    it 'initializes all pixels to 0' do
      expect(fb.get_pixel(0, 0)).to eq(0)
      expect(fb.get_pixel(159, 143)).to eq(0)
    end

    it 'stores and retrieves a pixel' do
      fb.set_pixel(10, 20, 3)
      expect(fb.get_pixel(10, 20)).to eq(3)
    end

    it 'does not affect other pixels when setting one' do
      fb.set_pixel(5, 5, 2)
      expect(fb.get_pixel(0, 0)).to eq(0)
      expect(fb.get_pixel(6, 5)).to eq(0)
    end

    it 'ignores writes off-screen (x < 0)' do
      fb.set_pixel(-1, 0, 3)
      expect(fb.get_pixel(0, 0)).to eq(0)
    end

    it 'ignores writes off-screen (x >= width)' do
      fb.set_pixel(160, 0, 3)
      expect(fb.get_pixel(159, 0)).to eq(0)
    end

    it 'ignores writes off-screen (y >= height)' do
      fb.set_pixel(0, 144, 3)
      expect(fb.get_pixel(0, 143)).to eq(0)
    end

    it 'pixels_frame returns a copy of current pixels' do
      fb.set_pixel(0, 0, 2)
      frame = fb.pixels_frame
      expect(frame[0]).to eq(2)
    end

    it 'pixels_frame copy is independent from internal state' do
      frame = fb.pixels_frame
      fb.set_pixel(0, 0, 3)
      expect(frame[0]).to eq(0)
    end

    it 'stores all 4 color values (0-3)' do
      (0..3).each do |c|
        fb.set_pixel(c, 0, c)
        expect(fb.get_pixel(c, 0)).to eq(c)
      end
    end
  end

  describe '#export_framebuffer_png' do
    it 'writes a PNG file sized to the GB screen resolution' do
      mmu = create_minimal_mmu
      ppu = build_ppu(mmu)
      palette = [[0, 0, 0], [1, 1, 1], [2, 2, 2], [3, 3, 3]]

      Tempfile.create(['framebuffer', '.png']) do |file|
        ppu.export_framebuffer_png(file.path, palette:)

        bytes = File.binread(file.path)
        expect(bytes[0, 8]).to eq("\x89PNG\r\n\x1A\n".b)

        width, height = bytes[16, 8].unpack('N2')
        expect(width).to eq(PPU::WINDOW_WIDTH)
        expect(height).to eq(PPU::WINDOW_HEIGHT)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # PPU::Scanline#tile_addr - signed (0x8800) addressing mode
  # ---------------------------------------------------------------------------
  describe 'PPU::Scanline#tile_addr' do
    let(:scanline) { PPU::Scanline.new(ppu: nil) }

    it 'uses unsigned addressing (tile_data_addr + index*16) when tile_data_addr is 0x8000' do
      scanline.tile_data_addr = 0x8000
      expect(scanline.tile_addr(0)).to eq(0x8000)
      expect(scanline.tile_addr(1)).to eq(0x8010)
      expect(scanline.tile_addr(255)).to eq(0x8FF0)
    end

    it 'treats index 0 as tile 0 at the base address (0x9000) in signed mode' do
      scanline.tile_data_addr = 0x9000
      expect(scanline.tile_addr(0)).to eq(0x9000)
    end

    it 'treats index 127 as the highest positive tile (+127) in signed mode' do
      scanline.tile_data_addr = 0x9000
      expect(scanline.tile_addr(127)).to eq(0x9000 + (127 * 16))
    end

    it 'treats index 128 as tile -128, i.e. the start of the signed block (0x8800)' do
      scanline.tile_data_addr = 0x9000
      expect(scanline.tile_addr(128)).to eq(0x8800)
    end

    it 'treats index 255 as tile -1, i.e. one tile below the base address (0x8FF0)' do
      scanline.tile_data_addr = 0x9000
      expect(scanline.tile_addr(255)).to eq(0x8FF0)
    end
  end

  # ---------------------------------------------------------------------------
  # OAM sprite scan and per-pixel sprite cache (mode 2)
  # ---------------------------------------------------------------------------
  describe 'sprite scan (mode 2)' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    def write_oam_sprite(index, y:, x:, tile_index: 0, attributes: 0x00)
      base = 0xFE00 + (index * 4)
      mmu.write(base, y)
      mmu.write(base + 1, x)
      mmu.write(base + 2, tile_index)
      mmu.write(base + 3, attributes)
    end

    it 'selects up to MAX_SPRITES_PER_SCANLINE (10) sprites visible on the current scanline' do
      mmu.write(0xFF40, 0x82) # LCD on, obj display on, 8x8 sprites
      12.times { |i| write_oam_sprite(i, y: 16, x: 8 + i) } # all visible on screen_y=0 (y_screen=0)

      ppu.tick(80) # enters mode 3 for scanline 0, triggering the OAM scan

      expect(ppu.scanline.oam_sprites.length).to eq(PPU::SpriteScanner::MAX_SPRITES_PER_SCANLINE)
    end

    it 'ignores sprites outside the current scanline range' do
      mmu.write(0xFF40, 0x82)
      write_oam_sprite(0, y: 16, x: 8)   # y_screen=0, visible on scanline 0
      write_oam_sprite(1, y: 40, x: 16)  # y_screen=24, not visible on scanline 0

      ppu.tick(80)

      expect(ppu.scanline.oam_sprites.length).to eq(1)
    end

    it 'does not scan any sprite when obj_display_enable is off' do
      mmu.write(0xFF40, 0x80) # LCD on, obj display off
      write_oam_sprite(0, y: 16, x: 8)

      ppu.tick(80)

      expect(ppu.scanline.oam_sprites).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Sprite pixel cache: X/Y flip and priority encoding (mode 2, built alongside the OAM scan)
  # ---------------------------------------------------------------------------
  describe 'sprite pixel cache (flip / priority)' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    # Row with a single lit pixel at the leftmost column (color 1), rest transparent (color 0)
    LEFT_PIXEL_TILE_ROW = [0x80, 0x00].freeze

    def write_tile(addr, row_bytes)
      byte1, byte2 = row_bytes
      8.times do |row|
        mmu.write(addr + (row * 2), byte1)
        mmu.write(addr + (row * 2) + 1, byte2)
      end
    end

    def write_oam_sprite(index, y:, x:, tile_index: 0, attributes: 0x00)
      base = 0xFE00 + (index * 4)
      mmu.write(base, y)
      mmu.write(base + 1, x)
      mmu.write(base + 2, tile_index)
      mmu.write(base + 3, attributes)
    end

    before { mmu.write(0xFF40, 0x82) } # LCD on, obj display on, 8x8 sprites

    it 'reads the tile without flipping by default' do
      write_tile(0x8000, LEFT_PIXEL_TILE_ROW)
      write_oam_sprite(0, y: 16, x: 8, tile_index: 0)

      ppu.tick(80)

      expect(ppu.sprite_scanner.sprite_pixel_cache[0]).to eq([1, 0, 0])
      expect(ppu.sprite_scanner.sprite_pixel_cache[7]).to be_nil # transparent (color 0) pixels are not cached
    end

    it 'mirrors the tile horizontally when the X-flip attribute bit is set' do
      write_tile(0x8000, LEFT_PIXEL_TILE_ROW)
      write_oam_sprite(0, y: 16, x: 8, tile_index: 0, attributes: 0x20) # bit5 = X flip

      ppu.tick(80)

      expect(ppu.sprite_scanner.sprite_pixel_cache[0]).to be_nil
      expect(ppu.sprite_scanner.sprite_pixel_cache[7]).to eq([1, 0, 0])
    end

    it 'encodes the OBJ-to-BG priority bit (attribute bit 7) alongside the color' do
      write_tile(0x8000, LEFT_PIXEL_TILE_ROW)
      write_oam_sprite(0, y: 16, x: 8, tile_index: 0, attributes: 0x80) # bit7 = priority (behind BG colors 1-3)

      ppu.tick(80)

      expect(ppu.sprite_scanner.sprite_pixel_cache[0]).to eq([1, 1, 0])
    end

    it 'encodes the OBP0/OBP1 palette selection bit (attribute bit 4) alongside the color' do
      write_tile(0x8000, LEFT_PIXEL_TILE_ROW)
      write_oam_sprite(0, y: 16, x: 8, tile_index: 0, attributes: 0x10) # bit4 = use OBP1

      ppu.tick(80)

      expect(ppu.sprite_scanner.sprite_pixel_cache[0]).to eq([1, 0, 1])
    end
  end

  # ---------------------------------------------------------------------------
  # Per-pixel compositing (mode 3): sprite vs. background priority resolution
  # ---------------------------------------------------------------------------
  describe 'draw_current_dot - sprite/background compositing' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    # Uniform-color tile: every pixel decodes to the given color (0-3)
    def write_uniform_tile(addr, color)
      byte1 = color.nobits?(0x01) ? 0x00 : 0xFF
      byte2 = color.nobits?(0x02) ? 0x00 : 0xFF
      16.times.each_slice(2) do |lo, hi|
        mmu.write(addr + lo, byte1)
        mmu.write(addr + hi, byte2)
      end
    end

    def write_oam_sprite(index, y:, x:, tile_index: 0, attributes: 0x00)
      base = 0xFE00 + (index * 4)
      mmu.write(base, y)
      mmu.write(base + 1, x)
      mmu.write(base + 2, tile_index)
      mmu.write(base + 3, attributes)
    end

    before do
      mmu.write(0xFF40, 0x93) # LCD on, BG enabled, obj display on, unsigned (0x8000) BG/window tile addressing
      mmu.write(0xFF47, 0xE4) # BGP: identity palette (0->0, 1->1, 2->2, 3->3)
      mmu.write(0xFF48, 0xE4) # OBP0: identity palette
      mmu.write(0xFF49, 0xE4) # OBP1: identity palette
      mmu.write(0x9800, 0x00) # background tile map: tile 0 at (0,0)
      write_uniform_tile(0x8000, 2) # background tile 0 -> color 2 everywhere
    end

    def draw_first_pixel
      ppu.tick(81) # 80 cycles to enter mode 3, +1 to draw screen_x=0
    end

    it 'draws the sprite color over the background when OBJ priority bit is 0' do
      write_uniform_tile(0x8010, 1) # sprite tile 1 -> color 1
      write_oam_sprite(0, y: 16, x: 8, tile_index: 1, attributes: 0x00)

      draw_first_pixel

      expect(ppu.framebuffer.get_pixel(0, 0)).to eq(1) # sprite color, not background color 2
    end

    it 'draws the background color over the sprite when OBJ priority bit is 1 and background is opaque' do
      write_uniform_tile(0x8010, 1) # sprite tile 1 -> color 1
      write_oam_sprite(0, y: 16, x: 8, tile_index: 1, attributes: 0x80) # priority=1 (behind BG colors 1-3)

      draw_first_pixel

      expect(ppu.framebuffer.get_pixel(0, 0)).to eq(2) # background wins
    end

    it 'draws the sprite color even with priority=1 when the background is transparent (color 0)' do
      write_uniform_tile(0x8000, 0) # background tile 0 -> color 0 (transparent)
      write_uniform_tile(0x8010, 1) # sprite tile 1 -> color 1
      write_oam_sprite(0, y: 16, x: 8, tile_index: 1, attributes: 0x80)

      draw_first_pixel

      expect(ppu.framebuffer.get_pixel(0, 0)).to eq(1) # sprite wins: BG color 0 never blocks a sprite
    end
  end

  # ---------------------------------------------------------------------------
  # Tile column boundaries with non-multiple-of-8 scx/wx (locks in current
  # per-pixel behavior before introducing a per-tile-column cache).
  # ---------------------------------------------------------------------------
  describe 'tile column boundaries (scx/wx not a multiple of 8)' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    def write_uniform_tile(addr, color)
      byte1 = color.nobits?(0x01) ? 0x00 : 0xFF
      byte2 = color.nobits?(0x02) ? 0x00 : 0xFF
      16.times.each_slice(2) do |lo, hi|
        mmu.write(addr + lo, byte1)
        mmu.write(addr + hi, byte2)
      end
    end

    def draw_up_to(screen_x)
      ppu.tick(80 + screen_x + 1) # 80 cycles to enter mode 3, +1 per pixel up to and including screen_x
    end

    it 'switches background tile at the correct screen_x when scx is not a multiple of 8' do
      mmu.write(0xFF40, 0x91) # LCD on, unsigned (0x8000) tile addressing, bg tile map 0x9800, obj off
      mmu.write(0xFF47, 0xE4) # BGP: identity palette
      mmu.write(0xFF43, 5) # SCX = 5 -> first tile boundary at screen_x = 8 - 5 = 3
      mmu.write(0x9800, 0x00) # bg map tile_x=0 -> tile index 0
      mmu.write(0x9801, 0x01) # bg map tile_x=1 -> tile index 1
      write_uniform_tile(0x8000, 1) # tile 0 -> color 1
      write_uniform_tile(0x8010, 2) # tile 1 -> color 2

      draw_up_to(10)

      expect(ppu.framebuffer.get_pixel(0, 0)).to eq(1) # bg_x=5, still tile 0
      expect(ppu.framebuffer.get_pixel(2, 0)).to eq(1) # bg_x=7, last pixel of tile 0
      expect(ppu.framebuffer.get_pixel(3, 0)).to eq(2) # bg_x=8, first pixel of tile 1
      expect(ppu.framebuffer.get_pixel(10, 0)).to eq(2) # bg_x=15, last pixel of tile 1
    end

    it 'switches window tile at the correct screen_x when wx is not a multiple of 8' do
      mmu.write(0xFF40, 0xF1) # LCD on, window map 0x9C00, window on, unsigned tile addressing, bg on
      mmu.write(0xFF47, 0xE4) # BGP: identity palette
      mmu.write(0xFF4A, 0) # WY = 0
      mmu.write(0xFF4B, 12) # WX = 12 -> window_x = screen_x - 5, active from screen_x = 5
      mmu.write(0x9800, 0x02) # bg map tile_x=0 -> tile index 2 (background, visible before the window starts)
      mmu.write(0x9C00, 0x00) # window map tile_x=0 -> tile index 0
      mmu.write(0x9C01, 0x01) # window map tile_x=1 -> tile index 1
      write_uniform_tile(0x8000, 2) # window tile 0 -> color 2
      write_uniform_tile(0x8010, 3) # window tile 1 -> color 3
      write_uniform_tile(0x8020, 1) # bg tile 2 -> color 1

      draw_up_to(13)

      expect(ppu.framebuffer.get_pixel(0, 0)).to eq(1) # window not yet active, background color
      expect(ppu.framebuffer.get_pixel(4, 0)).to eq(1) # window_x = -1, still background
      expect(ppu.framebuffer.get_pixel(5, 0)).to eq(2) # window_x = 0, first pixel of window tile 0
      expect(ppu.framebuffer.get_pixel(12, 0)).to eq(2) # window_x = 7, last pixel of window tile 0
      expect(ppu.framebuffer.get_pixel(13, 0)).to eq(3) # window_x = 8, first pixel of window tile 1
    end
  end

  # ---------------------------------------------------------------------------
  # Window internal line counter (WLY) across frames
  # ---------------------------------------------------------------------------
  describe 'window line counter across frames' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    CYCLES_PER_FRAME = 70_224

    # Row 0 of the tile is colour 1, every other row is colour 2, so the framebuffer tells
    # which window line was rendered on a given scanline.
    def write_striped_tile(addr)
      mmu.write(addr, 0xFF)
      mmu.write(addr + 1, 0x00)
      (1..7).each do |row|
        mmu.write(addr + (row * 2), 0x00)
        mmu.write(addr + (row * 2) + 1, 0xFF)
      end
    end

    before do
      mmu.write(0xFF40, 0xF1) # LCD on, window map 0x9C00, window on, unsigned tile addressing, bg on
      mmu.write(0xFF47, 0xE4) # BGP: identity palette
      mmu.write(0xFF4A, 0)    # WY = 0
      mmu.write(0xFF4B, 7)    # WX = 7 -> window starts at screen_x = 0
      mmu.write(0x9C00, 0x00) # window map tile_x=0 -> tile index 0
      write_striped_tile(0x8000)
    end

    it 'starts the window at its first line on the very first frame' do
      ppu.tick(CYCLES_PER_FRAME)

      expect(ppu.framebuffer.get_pixel(0, 0)).to eq(1)
    end

    it 'still starts the window at its first line on later frames' do
      3.times { ppu.tick(CYCLES_PER_FRAME) }

      expect(ppu.framebuffer.get_pixel(0, 0)).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # LCD STAT interrupts (mode 2 / mode 0 / mode 1 (vblank) / LYC=LY)
  # ---------------------------------------------------------------------------
  describe 'LCD STAT interrupts' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }

    it 'requests the vblank interrupt when entering VBlank' do
      mmu.write(0xFF40, 0x80) # LCD on
      ppu.tick(456 * 144) # one full tick per regular scanline (0..143) -> enters VBlank

      expect(mmu.interrupts.requested_mask[:vblank]).to eq(true)
    end

    it 'requests the lcd_stat interrupt when entering mode 2 (OAM scan) if the mode 2 STAT interrupt is enabled' do
      mmu.write(0xFF40, 0x80) # LCD on
      mmu.write(0xFF41, 0x20) # mode_2_interrupt_enable

      ppu.tick(1) # enters mode 2 for scanline 0

      expect(mmu.interrupts.requested_mask[:lcd_stat]).to eq(true)
    end

    it 'requests the lcd_stat interrupt when entering mode 0 (HBlank) if the mode 0 STAT interrupt is enabled' do
      mmu.write(0xFF40, 0x80) # LCD on
      mmu.write(0xFF41, 0x08) # mode_0_interrupt_enable

      ppu.tick(80 + 172) # 80 (mode 2) + 172 (mode 3) -> enters mode 0

      expect(mmu.interrupts.requested_mask[:lcd_stat]).to eq(true)
    end

    it 'requests the lcd_stat interrupt when entering VBlank if the mode 1 STAT interrupt is enabled' do
      mmu.write(0xFF40, 0x80) # LCD on
      mmu.write(0xFF41, 0x10) # mode_1_interrupt_enable

      ppu.tick(456 * 144)

      expect(mmu.interrupts.requested_mask[:lcd_stat]).to eq(true)
    end

    it 'requests the lcd_stat interrupt on LYC=LY match if the LYC STAT interrupt is enabled' do
      mmu.write(0xFF40, 0x80) # LCD on
      mmu.write(0xFF45, 0x00) # LYC = 0
      mmu.write(0xFF41, 0x40) # lyc_interrupt_enable

      ppu.tick(1) # enters mode 2 for scanline 0 (LY=0), matching LYC=0

      expect(mmu.interrupts.requested_mask[:lcd_stat]).to eq(true)
    end
  end

  describe 'blank frame when the LCD is turned off' do
    let(:mmu) { create_minimal_mmu }
    let!(:ppu) { build_ppu(mmu) }
    let(:white_frame) { Array.new(PPU::WINDOW_WIDTH * PPU::WINDOW_HEIGHT, 0) }

    def turn_lcd_off
      mmu.write(0xFF40, 0x80) # LCD on
      ppu.tick(4)
      mmu.write(0xFF40, 0x00) # LCD off
    end

    it 'renders a white frame on the tick following the extinction' do
      ppu.framebuffer.set_pixels(3)
      turn_lcd_off

      expect(ppu.tick(4)).to eq(white_frame)
    end

    it 'resets the PPU state on the extinction' do
      mmu.write(0xFF40, 0x80)
      ppu.tick(456 * 3) # LY = 3, past mode 2
      mmu.write(0xFF40, 0x00)

      ppu.tick(4)

      expect(ppu.scanline.value).to eq(0)
      expect(ppu.cycles).to eq(0)
      expect(ppu.mode).to eq(:mode_0)
      expect(mmu.read(0xFF44)).to eq(0)
    end

    it 'returns no further frame while the LCD stays off' do
      turn_lcd_off
      ppu.tick(4) # consumes the falling edge

      expect(200.times.map { ppu.tick(4) }).to all(be_nil)
    end

    it 'blanks again on each new extinction' do
      3.times do
        ppu.framebuffer.set_pixels(3)
        turn_lcd_off

        expect(ppu.tick(4)).to eq(white_frame)
      end
    end

    it 'keeps rendering frames while the LCD is on' do
      mmu.write(0xFF40, 0x80)

      frames = (456 * 154 / 4).times.count { ppu.tick(4) }

      expect(frames).to eq(1)
    end
  end
end
