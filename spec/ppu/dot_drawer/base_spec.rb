# frozen_string_literal: true

require_relative '../../../lib/ppu/dot_drawer/base'
require_relative '../../../lib/ppu/memory'

RSpec.describe PPU::DotDrawer::Base do
  let(:vram) { PPU::Memory.new(size: 0x2000, base_addr: 0x8000) }

  subject(:base) do
    described_class.new(bg_palette: double('bg_palette'), obj_palette: double('obj_palette'),
                        scanline: double('scanline'), sprite_scanner: double('sprite_scanner'), vram:)
  end

  describe '#read_vram' do
    it 'delegates to the injected vram, defaulting length and bank' do
      vram.write(0x8000, 0x42)

      expect(base.read_vram(0x8000)).to eq(0x42)
    end

    it 'forwards an explicit length and bank' do
      vram.write(0x8000, 0x11, bank: 0)

      expect(base.read_vram(0x8000, length: 1, bank: 0)).to eq(0x11)
    end
  end

  describe '#reset_caches!' do
    it 'resets the per-column tile x caches to -1, a sentinel that never matches a real tile_x' do
      base.instance_variable_set(:@bg_tile_x_cache, 5)
      base.instance_variable_set(:@win_tile_x_cache, 5)

      base.reset_caches!

      expect(base.instance_variable_get(:@bg_tile_x_cache)).to eq(-1)
      expect(base.instance_variable_get(:@win_tile_x_cache)).to eq(-1)
    end

    it 'clears the decoded tile and attribute caches for the current column' do
      base.instance_variable_set(:@bg_tile_cache, :stale)
      base.instance_variable_set(:@win_tile_cache, :stale)
      base.instance_variable_set(:@bg_tile_attr_cache, :stale)
      base.instance_variable_set(:@win_tile_attr_cache, :stale)

      base.reset_caches!

      expect(base.instance_variable_get(:@bg_tile_cache)).to be_nil
      expect(base.instance_variable_get(:@win_tile_cache)).to be_nil
      expect(base.instance_variable_get(:@bg_tile_attr_cache)).to be_nil
      expect(base.instance_variable_get(:@win_tile_attr_cache)).to be_nil
    end
  end

  describe '#reset_tile_column_caches!' do
    it 'clears the tile and tile attribute Hashes' do
      base.tile_cache[[0, 0x8000]] = :some_tile
      base.tile_attr_cache[0x9800] = 0x03

      base.reset_tile_column_caches!

      expect(base.tile_cache).to be_empty
      expect(base.tile_attr_cache).to be_empty
    end
  end

  describe 'window line counter' do
    it 'does not advance the window line unless the window was actually used this scanline' do
      base.update_window_line_counter!

      expect(base.instance_variable_get(:@window_line_counter)).to eq(0)
    end

    it 'advances the window line once, then clears the used-this-scanline flag' do
      base.instance_variable_set(:@window_used_this_scanline, true)

      base.update_window_line_counter!

      expect(base.instance_variable_get(:@window_line_counter)).to eq(1)
      expect(base.instance_variable_get(:@window_used_this_scanline)).to eq(false)
    end

    it 'resets the window line counter back to 0' do
      base.instance_variable_set(:@window_line_counter, 12)

      base.reset_window_line_state!

      expect(base.instance_variable_get(:@window_line_counter)).to eq(0)
    end
  end
end
