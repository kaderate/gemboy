$LOAD_PATH.unshift(File.expand_path('/home/user/gemboy/lib'))
require 'game_agents/zelda/scenarios'
require 'game_agents/zelda/screen_grid'
require 'game_agents/zelda/screen_map'
require 'game_agents/zelda/tile_classifier'

no_excl = []
cpu, ppu, apu, mmu, keys = Zelda::Scenarios.front_yard
grid = Zelda::ScreenGrid.load('/home/user/gemboy/lib/game_agents/zelda/data/screen_maps/overworld_front_yard.json')

def scroll(mmu)
  [mmu.read(0xFF43), mmu.read(0xFF42)]
end

puts "spawn scroll: #{scroll(mmu).inspect}"

# Known non-exit direction: [5,5] -> down = ok (interior of the mapped area)
before = scroll(mmu)
outcome, bc, ac = Zelda::TileClassifier.probe(cpu, ppu, apu, keys, mmu, :down, stationary_positions: no_excl, retries: 20)
after = scroll(mmu)
puts "[5,5]->down (known :ok): outcome=#{outcome} scroll before=#{before.inspect} after=#{after.inspect} changed=#{before != after}"

# navigate to [8,5], known exit south
Zelda::ScreenMap.navigate!(cpu, ppu, apu, keys, mmu, grid, [8, 5], stationary_positions: no_excl)
before2 = scroll(mmu)
outcome2, bc2, ac2 = Zelda::TileClassifier.probe(cpu, ppu, apu, keys, mmu, :down, stationary_positions: no_excl, retries: 20)
after2 = scroll(mmu)
puts "[8,5]->down (known :exit): outcome=#{outcome2} scroll before=#{before2.inspect} after=#{after2.inspect} changed=#{before2 != after2}"
