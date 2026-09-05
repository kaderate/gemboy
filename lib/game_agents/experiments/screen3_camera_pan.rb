# frozen_string_literal: true

# One-off diagnostic kept for the record: overworld_screen3's camera pans smoothly as Link
# approaches its edges, so a "fixed" background landmark's OAM position (e.g. the house's
# corner-post decor, tile 26) drifts by tens of pixels between reads that are only a few
# tile-moves apart. This is why chasing a remembered OAM coordinate toward the house2 door
# (house2_door_approach.rb's earlier attempts) kept missing -- switched to visually locating the
# door in a screenshot instead. See ZELDA_BACKLOG.md's "RoomMap::Recorder" section.
$LOAD_PATH.unshift(File.expand_path('../..', __dir__))
require 'game_agents/zelda/scenarios'

cpu, ppu, apu, mmu, keys = Zelda::Scenarios.villager_screen
no_excl = []

%i[down up left right].each do |dir|
  5.times { move_tiles(cpu, ppu, apu, keys, mmu, dir, 1, stationary_positions: no_excl) }
  run_steps(cpu, ppu, apu, 400_000)
  pos = find_link(cpu, ppu, apu, mmu, stationary_positions: no_excl)
  landmark = oam_sprites(mmu).find { |s| s[:tile] == 84 } # top-left corner-post decor
  puts "after 5x #{dir}: link=#{pos.inspect} landmark(tile 84)=#{landmark.inspect}"
end
