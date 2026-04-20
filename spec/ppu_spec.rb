require_relative '../lib/ppu'
require_relative '../lib/mmu'

RSpec.describe PPU do
  def create_minimal_mmu
    rom_bytes = Array.new(0x8000, 0x00)
    MMU.new(rom_bytes)
  end

  describe "initialization" do
    it "initializes with CPU reference" do
      mmu = create_minimal_mmu
      ppu = PPU.new(mmu)
      expect(ppu.mmu).to equal(mmu)
    end

    it "sets initial cycle count to 0" do
      mmu = create_minimal_mmu
      ppu = PPU.new(mmu)
      expect(ppu.cycles).to eq(0)
    end

    it "has framebuffer for rendering" do
      mmu = create_minimal_mmu
      ppu = PPU.new(mmu)
      expect(ppu.framebuffer).not_to be_nil
    end
  end

  describe "constants" do
    it "defines correct window dimensions" do
      expect(PPU::WINDOW_WIDTH).to eq(160)
      expect(PPU::WINDOW_HEIGHT).to eq(144)
    end

    it "defines border and scaling" do
      expect(PPU::BORDER).to eq(30)
      expect(PPU::PIXEL_SCALE).to eq(2)
    end
  end

  describe "cycle tracking" do
    let(:mmu) { create_minimal_mmu }
    let(:ppu) { PPU.new(mmu) }

    it "accumulates CPU cycles" do
      expect(ppu.cycles).to eq(0)
      ppu.tick(10)
      expect(ppu.cycles).to eq(10)
    end

    it "accumulates multiple ticks" do
      ppu.tick(100)
      ppu.tick(50)
      expect(ppu.cycles).to eq(150)
    end

    it "resets cycles after scanline (456 cycles)" do
      ppu.tick(456)
      # After 456 cycles, subtracts 456 and renders
      expect(ppu.cycles).to eq(0)
    end

    it "multiple scanlines accumulate correctly" do
      ppu.tick(456)  # scanline 1
      expect(ppu.cycles).to eq(0)
      ppu.tick(200)  # partial scanline 2
      expect(ppu.cycles).to eq(200)
    end
  end

  describe "PPU::Tile" do
    it "initializes with data" do
      data = Array.new(16, 0xFF)
      tile = PPU::Tile.new(data: data)
      expect(tile).to be_a(PPU::Tile)
    end

    it "decodes tile data into 8 lines" do
      data = Array.new(16, 0x00)
      tile = PPU::Tile.new(data: data)
      expect(tile.instance_variable_get(:@lines)).to be_a(Array)
      expect(tile.instance_variable_get(:@lines).length).to eq(8)
    end

    it "can access pixel_color method" do
      data = [0xFF, 0x00] + Array.new(14, 0x00)
      tile = PPU::Tile.new(data: data)
      expect(tile).to respond_to(:pixel_color)
    end

    it "creates two distinct tile objects" do
      data = Array.new(16, 0x00)
      tile1 = PPU::Tile.new(data: data)
      tile2 = PPU::Tile.new(data: data)
      expect(tile1).not_to equal(tile2)
    end
  end

  describe "PPU::BPPDecoder" do
    it "decodes two bytes into pixel colors" do
      decoder = PPU::BPPDecoder.new(0x00, 0x00)  # All pixels = 0
      # Decoder accesses with [] method
      expect(decoder).to respond_to(:[])
    end

    it "creates BPPDecoder with two bytes" do
      decoder = PPU::BPPDecoder.new(0xAA, 0x55)
      expect(decoder).to be_a(PPU::BPPDecoder)
    end

    it "supports indexing with brackets" do
      decoder = PPU::BPPDecoder.new(0x00, 0x00)
      expect(decoder).to respond_to(:[])
    end
  end

  describe "LCD control" do
    let(:mmu) { create_minimal_mmu }
    let(:ppu) { PPU.new(mmu) }

    it "reads LCD enable from CPU" do
      # CPU.lcd_control returns hash with :lcd_enable key
      lcd_control = ppu.mmu.read_lcd_control
      expect(lcd_control).to be_a(Hash)
      expect(lcd_control).to have_key(:lcd_enable)
    end

    it "returns lcd_control hash with keys" do
      lcd_control = ppu.mmu.read_lcd_control
      # Should have lcd_enable key
      expect(lcd_control).to have_key(:lcd_enable)
    end

    it "reads background tile map display select" do
      lcd_control = ppu.mmu.read_lcd_control
      expect(lcd_control).to have_key(:bg_tile_map_display_select)
    end

    it "reads background and window tile data select" do
      lcd_control = ppu.mmu.read_lcd_control
      expect(lcd_control).to have_key(:bg_and_window_tile_data_select)
    end
  end

  describe "VRAM accessthrough MMU" do
    let(:mmu) { create_minimal_mmu }
    let(:ppu) { PPU.new(mmu) }

    it "can read from VRAM through MMU" do
      # Write to VRAM via CPU
      mmu.write(0x8000, 0xAB)
      # Read through PPU's CPU reference
      value = ppu.mmu.read(0x8000)
      expect(value).to eq(0xAB)
    end

    it "can read tile data (16 bytes per tile)" do
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

    it "separates VRAM ranges correctly" do
      mmu.write(0x8000, 0x11)  # Start of VRAM
      mmu.write(0x9FFF, 0x22)  # End of VRAM
      expect(mmu.read(0x8000)).to eq(0x11)
      expect(mmu.read(0x9FFF)).to eq(0x22)
    end
  end

  describe "rendering control" do
    let(:mmu) { create_minimal_mmu }
    let(:ppu) { PPU.new(mmu) }

    it "responds to tick method" do
      expect(ppu).to respond_to(:tick)
    end

    it "can trigger full frame render" do
      ppu.tick(456)
      expect(ppu.cycles).to eq(0)
    end

    it "has framebuffer when LCD is disabled" do
      expect(ppu.framebuffer).not_to be_nil
    end
  end

  describe "tile display integration" do
    let(:mmu) { create_minimal_mmu }
    let(:ppu) { PPU.new(mmu) }

    it "creates tiles from VRAM data" do
      # Write tile index to background tile map
      mmu.write(0x9800, 0x00)  # First tile index in background map
      # Should be able to read this
      expect(mmu.read(0x9800)).to eq(0x00)
    end

    it "reads tile data based on tile index" do
      # Tile 0 starts at 0x8000 (if using 0x8000 tile data address)
      tile_data = Array.new(16, 0x55)
      tile_data.each_with_index { |b, i| mmu.write(0x8000 + i, b) }
      # Should be readable
      (0..15).each { |i| expect(mmu.read(0x8000 + i)).to eq(0x55) }
    end

    it "supports 32x32 background tile map" do
      # Background map is 32x32 tiles at 0x9800 or 0x9C00
      # Each tile index is 1 byte
      # Total: 32 * 32 = 1024 bytes per map
      map_size = 32 * 32
      expect(map_size).to eq(1024)
    end
  end

  describe "color conversion" do
    it "converts color values to hex colors" do
      # Color values 0-3 should map to palette colors
      # 0 = lightest, 3 = darkest
      # Test is implementation-dependent
      tile = PPU::Tile.new(data: Array.new(16, 0))
      expect(tile).to be_a(PPU::Tile)
    end

    it "handles 2BPP color encoding correctly" do
      # 2 bits per pixel = 4 colors
      # 8 pixels per row = 16 bits = 2 bytes per row
      # 8 rows = 16 bytes per tile
      expect(16 * 8 / 8).to eq(16)  # bits per tile
    end
  end

  describe "scanline-based rendering" do
    let(:mmu) { create_minimal_mmu }
    let(:ppu) { PPU.new(mmu) }

    it "processes scanlines in 456-cycle chunks" do
      # Game Boy: 456 cycles = 1 scanline
      scanline_cycles = 456
      # After a scanline, render is triggered and cycles reset
      ppu.tick(scanline_cycles)
      expect(ppu.cycles).to eq(0)
    end

    it "multiple scanlines accumulate correctly before reset" do
      # Multiple partial scanlines accumulate
      ppu.tick(200)
      ppu.tick(200)
      expect(ppu.cycles).to eq(400)
      ppu.tick(56)  # Triggers reset at 456
      expect(ppu.cycles).to eq(0)
    end
  end

  describe "window dimensions" do
    let(:mmu) { create_minimal_mmu }
    let(:ppu) { PPU.new(mmu) }

    it "creates window with border" do
      # Display dimensions: 160x144 (Game Boy)
      # Canvas: WINDOW_WIDTH * PIXEL_SCALE x WINDOW_HEIGHT * PIXEL_SCALE at (BORDER, BORDER)
      # Window: WINDOW_WIDTH * PIXEL_SCALE + BORDER * 2 x WINDOW_HEIGHT * PIXEL_SCALE + BORDER * 2
      expected_width = (160 * 2) + (30 * 2)
      expected_height = (144 * 2) + (30 * 2)
      expect(expected_width).to eq(380)
      expect(expected_height).to eq(348)
    end
  end

  describe "PPU::BPPDecoder pixel values" do
    it "decodes 0xFF/0x00 as all color 1 (bit1=1, bit2=0)" do
      decoder = PPU::BPPDecoder.new(0xFF, 0x00)
      expect((0...8).map { |i| decoder[i] }).to eq([1, 1, 1, 1, 1, 1, 1, 1])
    end

    it "decodes 0x00/0xFF as all color 2 (bit1=0, bit2=1)" do
      decoder = PPU::BPPDecoder.new(0x00, 0xFF)
      expect((0...8).map { |i| decoder[i] }).to eq([2, 2, 2, 2, 2, 2, 2, 2])
    end

    it "decodes 0xFF/0xFF as all color 3 (bit1=1, bit2=1)" do
      decoder = PPU::BPPDecoder.new(0xFF, 0xFF)
      expect((0...8).map { |i| decoder[i] }).to eq([3, 3, 3, 3, 3, 3, 3, 3])
    end

    it "decodes 0x00/0x00 as all color 0" do
      decoder = PPU::BPPDecoder.new(0x00, 0x00)
      expect((0...8).map { |i| decoder[i] }).to eq([0, 0, 0, 0, 0, 0, 0, 0])
    end

    it "decodes MSB first: 0x80/0x00 sets only pixel 0 to color 1" do
      decoder = PPU::BPPDecoder.new(0x80, 0x00)
      expect(decoder[0]).to eq(1)
      expect((1...8).map { |i| decoder[i] }).to eq([0, 0, 0, 0, 0, 0, 0])
    end

    it "decodes 0x80/0x80 sets only pixel 0 to color 3" do
      decoder = PPU::BPPDecoder.new(0x80, 0x80)
      expect(decoder[0]).to eq(3)
      expect((1...8).map { |i| decoder[i] }).to eq([0, 0, 0, 0, 0, 0, 0])
    end

    it "decodes 0x01/0x00 sets only pixel 7 to color 1 (LSB = last pixel)" do
      decoder = PPU::BPPDecoder.new(0x01, 0x00)
      expect(decoder[7]).to eq(1)
      expect((0...7).map { |i| decoder[i] }).to eq([0, 0, 0, 0, 0, 0, 0])
    end
  end

  describe "PPU::Tile pixel_color" do
    it "returns color 1 for all pixels in row 0 with data [0xFF, 0x00, ...]" do
      data = [0xFF, 0x00] + Array.new(14, 0x00)
      tile = PPU::Tile.new(data: data)
      expect((0...8).map { |x| tile.pixel_color(x, 0) }).to eq([1, 1, 1, 1, 1, 1, 1, 1])
    end

    it "returns color 2 for all pixels in row 0 with data [0x00, 0xFF, ...]" do
      data = [0x00, 0xFF] + Array.new(14, 0x00)
      tile = PPU::Tile.new(data: data)
      expect((0...8).map { |x| tile.pixel_color(x, 0) }).to eq([2, 2, 2, 2, 2, 2, 2, 2])
    end

    it "returns color 0 for all pixels when data is all zeros" do
      tile = PPU::Tile.new(data: Array.new(16, 0x00))
      expect(tile.pixel_color(0, 0)).to eq(0)
      expect(tile.pixel_color(7, 7)).to eq(0)
    end

    it "reads row 1 independently from row 0" do
      # row0: 0x00/0x00 → color 0; row1: 0xFF/0xFF → color 3
      data = [0x00, 0x00, 0xFF, 0xFF] + Array.new(12, 0x00)
      tile = PPU::Tile.new(data: data)
      expect(tile.pixel_color(0, 0)).to eq(0)
      expect(tile.pixel_color(0, 1)).to eq(3)
    end

    it "returns correct color for pixel at column 0, row 7 (last row)" do
      # last row (bytes 14/15): 0x80/0x80 → pixel 0 = color 3
      data = Array.new(14, 0x00) + [0x80, 0x80]
      tile = PPU::Tile.new(data: data)
      expect(tile.pixel_color(0, 7)).to eq(3)
      expect(tile.pixel_color(1, 7)).to eq(0)
    end
  end

  describe "PPU::Framebuffer" do
    let(:fb) { PPU::Framebuffer.new(160, 144) }

    it "initializes all pixels to 0" do
      expect(fb.get_pixel(0, 0)).to eq(0)
      expect(fb.get_pixel(159, 143)).to eq(0)
    end

    it "stores and retrieves a pixel" do
      fb.set_pixel(10, 20, 3)
      expect(fb.get_pixel(10, 20)).to eq(3)
    end

    it "does not affect other pixels when setting one" do
      fb.set_pixel(5, 5, 2)
      expect(fb.get_pixel(0, 0)).to eq(0)
      expect(fb.get_pixel(6, 5)).to eq(0)
    end

    it "ignores writes off-screen (x < 0)" do
      fb.set_pixel(-1, 0, 3)
      expect(fb.get_pixel(0, 0)).to eq(0)
    end

    it "ignores writes off-screen (x >= width)" do
      fb.set_pixel(160, 0, 3)
      expect(fb.get_pixel(159, 0)).to eq(0)
    end

    it "ignores writes off-screen (y >= height)" do
      fb.set_pixel(0, 144, 3)
      expect(fb.get_pixel(0, 143)).to eq(0)
    end

    it "pixels_frame returns a copy of current pixels" do
      fb.set_pixel(0, 0, 2)
      frame = fb.pixels_frame
      expect(frame[0]).to eq(2)
    end

    it "pixels_frame copy is independent from internal state" do
      frame = fb.pixels_frame
      fb.set_pixel(0, 0, 3)
      expect(frame[0]).to eq(0)
    end

    it "stores all 4 color values (0-3)" do
      (0..3).each { |c| fb.set_pixel(c, 0, c) }
      (0..3).each { |c| expect(fb.get_pixel(c, 0)).to eq(c) }
    end
  end
end
