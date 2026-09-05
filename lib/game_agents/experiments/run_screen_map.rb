# frozen_string_literal: true

# Runs ScreenMap.build on one named checkpoint with a persistent, shared TileCatalog (loaded from
# and saved back to lib/game_agents/zelda/data/tile_catalog.json), and saves the resulting grid to
# lib/game_agents/zelda/data/screen_maps/<screen>.json. Meant to be run once per screen as the
# village gets mapped -- each run enriches the catalog for the next one.
#
# Usage: bundle exec ruby lib/game_agents/experiments/run_screen_map.rb <checkpoint_method> <screen_name> [max_cells] [retries]
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

catalog_path = File.expand_path('../data/tile_catalog.json', __dir__)
grid_path = File.expand_path("../data/screen_maps/#{screen_name}.json", __dir__)

catalog = Zelda::TileCatalog.load(catalog_path)
puts "loaded catalog: #{catalog.size} known tiles"

cpu, ppu, apu, mmu, keys = Zelda::Scenarios.public_send(checkpoint_method)
no_excl = []
reset = -> { Zelda::Checkpoint.load(Zelda::Scenarios.checkpoint_path(checkpoint_method.to_s)) }
stats = {}

t0 = Time.now
grid, status = Zelda::ScreenMap.build(cpu, ppu, apu, keys, mmu, screen_name:, catalog:, stationary_positions: no_excl,
                                                                max_cells:, retries:, reset:, stats:)
puts "status=#{status} in #{(Time.now - t0).round(1)}s, cells=#{grid.cells.size}, stats=#{stats}, " \
     "catalog now #{catalog.size} tiles"

catalog.save(catalog_path)
grid.save(grid_path)
puts "saved catalog -> #{catalog_path}"
puts "saved grid -> #{grid_path}"
