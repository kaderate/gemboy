# frozen_string_literal: true

# One-off diagnostic kept for the record: this is what found the villager_screen checkpoint's
# mid-scroll bug (see ZELDA_BACKLOG.md's "RoomMap::Recorder" section and the scenarios.rb fix
# commit). Every direction probed from that checkpoint produced an identical, direction-
# independent ~54px jump -- suspicious enough to check whether the checkpoint itself was mid-
# animation. Confirmed here: with ZERO input, Link's OAM position kept drifting for ~200k cycles
# before settling. Since scenarios.rb now settles 400k cycles before saving, running this against
# the current checkpoint should show NO drift in the first loop (a live confirmation the fix
# holds) -- the historical bug is preserved below as a regression check, not a live repro.
$LOAD_PATH.unshift(File.expand_path('../..', __dir__))
require 'game_agents/zelda/scenarios'

cpu, ppu, apu, mmu, keys = Zelda::Scenarios.villager_screen

puts '-- position with zero input over time (proves the checkpoint was saved mid-scroll) --'
10.times do |i|
  run_steps(cpu, ppu, apu, 200_000)
  link = oam_sprites(mmu).find { |s| s[:tile] == 0 }
  puts "t=#{i}: link=#{link.inspect}"
end

puts '-- after the fix (scenarios.rb settles 400k cycles before saving), every direction from ' \
     'this checkpoint should now produce only a small real ~2px nudge, not a phantom jump --'
%i[up down left right].each do |dir|
  before = find_link(cpu, ppu, apu, mmu, stationary_positions: [])
  move_tiles(cpu, ppu, apu, keys, mmu, dir, 1, stationary_positions: [])
  after = find_link(cpu, ppu, apu, mmu, stationary_positions: [])
  delta = before && after ? Math.sqrt(((after[:y] - before[:y])**2) + ((after[:x] - before[:x])**2)).round(1) : nil
  puts "#{dir}: before=#{before} after=#{after} delta=#{delta}"
end
