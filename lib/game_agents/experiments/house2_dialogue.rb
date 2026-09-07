# frozen_string_literal: true
# Found a named NPC in house2_interior via approach 2 of house2_interact2.rb: "Pépé le Ramollo" --
# the sprite pair previously guessed as part of the "pot cluster" (tile 112-118) is actually this
# NPC, dialogue box confirmed. Capture the full dialogue page by page (same method used for
# Tarkin/the 2nd starting-house NPC/the overworld villager -- see ZELDA_BACKLOG.md).
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

reached = Zelda::ScreenMap.navigate!(cpu, ppu, apu, keys, mmu, grid, [4, 3], stationary_positions: no_excl, retries: 20)
puts "reached [4,3]: #{reached}"
tap_key(cpu, ppu, apu, keys, :right, hold: 30_000, release: 500_000)
interact(cpu, ppu, apu, keys)
snap(ppu, '/tmp/claude-0/-home-user-gemboy/41152e51-151e-5539-a944-68e4e7cb8b11/scratchpad/house2_dialogue_page1.png')
puts 'page 1 captured'

10.times do |i|
  interact(cpu, ppu, apu, keys)
  snap(ppu, "/tmp/claude-0/-home-user-gemboy/41152e51-151e-5539-a944-68e4e7cb8b11/scratchpad/house2_dialogue_page#{i + 2}.png")
  puts "page #{i + 2} captured"
end
