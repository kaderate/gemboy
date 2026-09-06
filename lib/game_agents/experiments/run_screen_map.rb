# frozen_string_literal: true

# Runs ScreenMap.build on one named checkpoint with a persistent, shared TileCatalog (loaded from
# and saved back to lib/game_agents/zelda/data/tile_catalog.json), and saves the resulting grid to
# lib/game_agents/zelda/data/screen_maps/<screen>.json. Meant to be run once per screen as the
# village gets mapped -- each run enriches the catalog for the next one.
#
# Usage: bundle exec ruby lib/game_agents/experiments/run_screen_map.rb <checkpoint_method> <screen_name> [max_cells] [retries]
require 'fileutils'
$stdout.sync = true # redirected stdout is fully buffered by default -- without this, progress
# output (see logger: below) doesn't actually appear until the process exits,
# making a stalled run indistinguishable from a slow one (see ZELDA_BACKLOG.md).
$LOAD_PATH.unshift(File.expand_path('../..', __dir__))
require 'game_agents/zelda/scenarios'
require 'game_agents/zelda/screen_map'
require 'game_agents/zelda/tile_catalog'
require 'game_agents/zelda/checkpoint'

checkpoint_method = ARGV[0] or raise ArgumentError,
                                     'usage: run_screen_map.rb <checkpoint_method> <screen_name> [max_cells] [retries]'
screen_name = ARGV[1] or raise ArgumentError, 'missing screen_name'
max_cells = (ARGV[2] || 20).to_i
retries = (ARGV[3] || 6).to_i

catalog_path = File.expand_path('../zelda/data/tile_catalog.json', __dir__)
grid_path = File.expand_path("../zelda/data/screen_maps/#{screen_name}.json", __dir__)

catalog = Zelda::TileCatalog.load(catalog_path)
puts "loaded catalog: #{catalog.size} known tiles"
FileUtils.mkdir_p(File.dirname(grid_path))

# A full exploration can run for tens of minutes; the grid/catalog only reach disk on a normal
# return below, so a hard kill (a wall-clock `timeout` wrapper included -- see
# ZELDA_BACKLOG.md's movement model) mid-build loses everything since the last save. `live_grid`
# gets a reference the moment ScreenMap.build creates it (see `on_grid_ready:`), so the trap
# below can save the real in-progress state instead of nothing.
live_grid = nil
save_progress = lambda {
  catalog.save(catalog_path)
  live_grid&.save(grid_path)
}
%w[TERM INT].each do |sig|
  Signal.trap(sig) do
    save_progress.call
    exit
  end
end

cpu, ppu, apu, mmu, keys = Zelda::Scenarios.public_send(checkpoint_method)
# Right after Tarkin's dialogue, Link's sprite renders in an idle pose (a non-tile-0 frame)
# find_link's tile-ID matching doesn't recognize -- with no exclusions, its fallback grabs the
# first OAM sprite (Tarkin) instead of Link, corrupting every distance measurement from spawn
# (see ZELDA_BACKLOG.md). STATIONARY_STARTING_HOUSE already lists exactly those NPC/decor
# positions for the interior screens that chain off it.
no_excl = checkpoint_method == 'after_shield_interior' ? Zelda::Scenarios::STATIONARY_STARTING_HOUSE : []
reset = -> { Zelda::Checkpoint.load(Zelda::Scenarios.checkpoint_path(checkpoint_method.to_s)) }
stats = {}

t0 = Time.now
logger = ->(msg) { puts msg }
grid, status = Zelda::ScreenMap.build(cpu, ppu, apu, keys, mmu, screen_name:, catalog:, stationary_positions: no_excl,
                                                                max_cells:, retries:, reset:, stats:, logger:,
                                                                on_grid_ready: ->(g) { live_grid = g })
puts "status=#{status} in #{(Time.now - t0).round(1)}s, cells=#{grid.cells.size}, stats=#{stats}, " \
     "catalog now #{catalog.size} tiles"

save_progress.call
puts "saved catalog -> #{catalog_path}"
puts "saved grid -> #{grid_path}"
