$LOAD_PATH.unshift(File.expand_path('/home/user/gemboy/lib'))
require 'game_agents/zelda/scenarios'
require 'game_agents/zelda/tile_classifier'

stat = Zelda::Scenarios::STATIONARY_STARTING_HOUSE
cpu, ppu, apu, mmu, keys = Zelda::Scenarios.after_shield_interior

def scroll(mmu)
  [mmu.read(0xFF43), mmu.read(0xFF42)]
end

pos0 = find_link(cpu, ppu, apu, mmu, stationary_positions: stat)
puts "spawn: #{pos0.inspect} cell=#{Zelda::TileClassifier.cell_for(pos0).inspect} scroll=#{scroll(mmu).inspect}"

outcome, bc, ac = Zelda::TileClassifier.probe(cpu, ppu, apu, keys, mmu, :down, stationary_positions: stat, retries: 20)
puts "[3,3]->down: outcome=#{outcome} before_cell=#{bc.inspect} after_cell=#{ac.inspect} scroll_now=#{scroll(mmu).inspect}"
