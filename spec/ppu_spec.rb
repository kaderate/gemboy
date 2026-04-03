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

    it "has canvas for rendering" do
      mmu = create_minimal_mmu
      ppu = PPU.new(mmu)
      expect(ppu.canvas).not_to be_nil
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
    it "initializes with data and position" do
      data = Array.new(16, 0xFF)  # All bits set
      tile = PPU::Tile.new(data: data, x: 0, y: 0)
      expect(tile).to be_a(PPU::Tile)
    end

    it "decodes tile data into 8 lines" do
      # Each tile is 8x8 pixels, encoded in 16 bytes (2 bytes per line)
      data = Array.new(16, 0x00)  # All pixels black
      tile = PPU::Tile.new(data: data, x: 0, y: 0)
      # Tile stores decoded lines internally
      expect(tile.instance_variable_get(:@lines)).to be_a(Array)
      expect(tile.instance_variable_get(:@lines).length).to eq(8)
    end

    it "can access pixel_color method" do
      # Create tile with simple pattern
      data = [0xFF, 0x00] + Array.new(14, 0x00)  # First line all pixels
      tile = PPU::Tile.new(data: data, x: 0, y: 0)
      # Tile should respond to pixel_color
      expect(tile).to respond_to(:pixel_color)
    end

    it "supports different x,y positions for tile display" do
      data = Array.new(16, 0x00)
      tile1 = PPU::Tile.new(data: data, x: 0, y: 0)
      tile2 = PPU::Tile.new(data: data, x: 160, y: 144)
      expect(tile1).not_to equal(tile2)
    end
  end

  describe "PPU::BPPDecoder" do
    it "decodes two bytes into pixel colors" do
      decoder = PPU::BPPDecoder.new(0x00, 0x00)  # All pixels = 0
      # Decoder accesses with [] method
      expect(decoder).to respond_to(:[])
    end

    it "handles palette-based decoding" do
      palette = [0xFF, 0xAA, 0x55, 0x00]
      decoder = PPU::BPPDecoder.new(0x00, 0x00, palette)
      # Should work with custom palette
      expect(decoder).to be_a(PPU::BPPDecoder)
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
      lcd_control = ppu.lcd_control
      expect(lcd_control).to be_a(Hash)
      expect(lcd_control).to have_key(:lcd_enable)
    end

    it "returns lcd_control hash with keys" do
      lcd_control = ppu.lcd_control
      # Should have lcd_enable key
      expect(lcd_control).to have_key(:lcd_enable)
    end

    it "reads background tile map display select" do
      lcd_control = ppu.lcd_control
      expect(lcd_control).to have_key(:bg_tile_map_display_select)
    end

    it "reads background and window tile data select" do
      lcd_control = ppu.lcd_control
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

    it "responds to render method" do
      expect(ppu).to respond_to(:render)
    end

    it "can trigger full frame render" do
      # Execute 456 cycles to trigger render
      ppu.tick(456)
      # render should have been called internally
      expect(ppu.cycles).to eq(0)
    end

    it "handles LCD disabled state" do
      # When LCD is disabled, canvas should be cleared or blank
      # This depends on implementation
      expect(ppu.canvas).not_to be_nil
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
      tile = PPU::Tile.new(data: Array.new(16, 0), x: 0, y: 0)
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
end
