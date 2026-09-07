# frozen_string_literal: true
# The second untested house2_interior sprite pair (tile 116/118 at ~(80,72), distinct IDs from
# Pépé le Ramollo's 112/114) -- approach from [5,4] facing up and try interact(), then try lifting.
$LOAD_PATH.unshift('/home/user/gemboy/lib')
require 'game_agents/zelda/scenarios'
require 'game_agents/zelda/screen_map'
require 'game_agents/zelda/screen_grid'
require 'game_agents/zelda/tile_classifier'
require 'utils/png_writer'

def snap(ppu, path, scale: 4)
  pixels = ppu.framebuffer.pixels_frame
  width = 160
  height = 144
  out_w = width * scale
  out_h = height * scale
  out = Array.new(out_w * out_h)
  (0...height).each do |y|
    (0...width).each do |x|
      color = pixels[(y * width) + x]
      scale.times { |dy| scale.times { |dx| out[((((y * scale) + dy) * out_w) + (x * scale) + dx)] = color } }
    end
  end
  PngWriter.write(path, out, width: out_w, height: out_h)
end

cpu, ppu, apu, mmu, keys = Zelda::Scenarios.house2_interior
no_excl = []
grid = Zelda::ScreenGrid.load('/home/user/gemboy/lib/game_agents/zelda/data/screen_maps/house2_interior.json')

reached = Zelda::ScreenMap.navigate!(cpu, ppu, apu, keys, mmu, grid, [5, 4], stationary_positions: no_excl, retries: 20)
puts "reached [5,4]: #{reached}"
tap_key(cpu, ppu, apu, keys, :up, hold: 30_000, release: 500_000)
sprites_before = oam_sprites(mmu)
puts "sprites before: #{sprites_before.size}"
5.times do |i|
  interact(cpu, ppu, apu, keys)
  snap(ppu, "/tmp/claude-0/-home-user-gemboy/41152e51-151e-5539-a944-68e4e7cb8b11/scratchpad/house2_sprite2_p#{i + 1}.png")
  puts "interact ##{i + 1} sprites=#{oam_sprites(mmu).size}"
end
pos = find_link(cpu, ppu, apu, mmu, stationary_positions: no_excl)
puts "final pos=#{pos.inspect}"
