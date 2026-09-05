# frozen_string_literal: true

# One-off exploration kept for the record: an attempt to enter house2_interior from
# overworld_screen3, guided by visually locating the door in a screenshot rather than chasing an
# OAM-relative landmark (which turned out to drift as the camera pans -- see
# screen3_camera_pan.rb). Consistently gets stuck at a stable collision wall around x=97 before
# reaching the door at ~(y=90, x=70) -- matches the prior session's "tall-grass hard-collision
# strip" finding in ZELDA_BACKLOG.md. Documents an unresolved navigation puzzle, not a working
# route: house2_interior is NOT one of the mapped rooms in data/room_maps/. Needs the tilemap-
# based walkable-grid approach (extract this screen's BG tilemap, route around the grass strip
# explicitly) rather than another greedy-movement attempt.
$LOAD_PATH.unshift(File.expand_path('../..', __dir__))
require 'game_agents/zelda/scenarios'

cpu, ppu, apu, mmu, keys = Zelda::Scenarios.villager_screen
no_excl = []

def greedy_to(cpu, ppu, apu, keys, mmu, target, no_excl, max_steps: 40, tol: 6)
  max_steps.times do
    pos = find_link(cpu, ppu, apu, mmu, stationary_positions: no_excl)
    if pos.nil?
      # This screen periodically blanks all OAM for dozens of frames (see RoomMap's :lost
      # recovery work) -- a transient nil isn't "we're lost", just bad timing. Wait it out.
      run_steps(cpu, ppu, apu, 600_000)
      pos = find_link(cpu, ppu, apu, mmu, stationary_positions: no_excl)
      return nil if pos.nil?
    end

    dy = target[:y] - pos[:y]
    dx = target[:x] - pos[:x]
    return pos if dy.abs <= tol && dx.abs <= tol

    dir = if dy.abs >= dx.abs
            dy.positive? ? :down : :up
          else
            (dx.positive? ? :right : :left)
          end
    moved = move_tiles(cpu, ppu, apu, keys, mmu, dir, 1, stationary_positions: no_excl)
    next if moved.positive?

    alt_dir = if dy.abs >= dx.abs
                dx.positive? ? :right : :left
              else
                (dy.positive? ? :down : :up)
              end
    move_tiles(cpu, ppu, apu, keys, mmu, alt_dir, 1, stationary_positions: no_excl)
  end
  find_link(cpu, ppu, apu, mmu, stationary_positions: no_excl)
end

# Visually located from a screenshot: the door is the dark rectangle at the house's bottom
# center, roughly native (y=90, x=70). Approach from just below it, then push up through it.
below_door = { y: 104, x: 70 }
pos = greedy_to(cpu, ppu, apu, keys, mmu, below_door, no_excl, max_steps: 40, tol: 6)
puts "below door: #{pos.inspect}"

10.times do |i|
  move_tiles(cpu, ppu, apu, keys, mmu, :up, 1, stationary_positions: no_excl)
  run_steps(cpu, ppu, apu, 300_000)
  pos = find_link(cpu, ppu, apu, mmu, stationary_positions: no_excl)
  puts "after up ##{i + 1}: #{pos.inspect} sprites=#{oam_sprites(mmu).size}"
end
puts "final OAM: #{oam_sprites(mmu).inspect}"
