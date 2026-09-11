# frozen_string_literal: true

# Cross-validation pass 2: does $FF98 flip sign on LEFT (X hyp), does $FF99 move on UP/DOWN but
# not RIGHT/LEFT (Y hyp), what about $FF9E (direction) and $FFF6/$FFF7 (room/map id) across a
# real screen transition (villager_screen -> screen3_north, a known scrolling exit)?
$LOAD_PATH.unshift(File.expand_path('/home/user/gemboy/lib'))
$LOAD_PATH.unshift(File.expand_path('/home/user/gemboy/profiling'))
require 'utils'
require_relative '/home/user/gemboy/lib/game_agents/zelda/checkpoint'

WATCH = {
  'X?' => 0xFF98,
  'X2?' => 0xFF9F,
  'Y?' => 0xFF99,
  'dir?' => 0xFF9E,
  'room?' => 0xFFF6,
  'map?' => 0xFFF7
}.freeze

def tap_dir(cpu, ppu, apu, mmu, keys, dir)
  keys.press(dir)
  run_steps(cpu, ppu, apu, 20_000)
  keys.clear
  run_steps(cpu, ppu, apu, 20_000)
end

def snap(mmu) = WATCH.transform_values { |a| mmu.read(a) }

def report(label, before, after)
  diffs = WATCH.keys.map do |k|
    if after[k] != before[k]
      format('%s=%d->%d (%+d)', k, before[k], after[k], after[k] - before[k])
    else
      "#{k}=#{before[k]}"
    end
  end
  puts "  #{label}: #{diffs.join(', ')}"
end

checkpoint_path = '/tmp/zelda_checkpoints/villager_screen.marshal'
cpu, ppu, apu, mmu, keys = Zelda::Checkpoint.load(checkpoint_path)

puts '=== LEFT x4 (expect X? to decrease, Y? flat) ==='
before = snap(mmu)
4.times do |i|
  tap_dir(cpu, ppu, apu, mmu, keys, :left)
  after = snap(mmu)
  report("tap #{i + 1}", before, after)
  before = after
end

puts "\n=== DOWN x4 (expect Y? to change, X? flat) ==="
4.times do |i|
  tap_dir(cpu, ppu, apu, mmu, keys, :down)
  after = snap(mmu)
  report("tap #{i + 1}", before, after)
  before = after
end

puts "\n=== UP x4 (expect Y? to flip sign vs DOWN) ==="
4.times do |i|
  tap_dir(cpu, ppu, apu, mmu, keys, :up)
  after = snap(mmu)
  report("tap #{i + 1}", before, after)
  before = after
end

# screen3_north checkpoint crosses a real scrolling transition from overworld_screen3 -- if room/map
# id are real, they should change exactly once, at the transition.
puts "\n=== room?/map? across a known screen transition (villager_screen -> screen3_north checkpoint) ==="
sc3n_path = '/tmp/zelda_checkpoints/screen3_north.marshal'
if File.exist?(sc3n_path)
  cpu2, ppu2, apu2, mmu2, = Zelda::Checkpoint.load(sc3n_path)
  puts "  villager_screen room?=#{mmu.read(0xFFF6)} map?=#{mmu.read(0xFFF7)}"
  puts "  screen3_north   room?=#{mmu2.read(0xFFF6)} map?=#{mmu2.read(0xFFF7)}"
else
  puts '  screen3_north checkpoint not found, skipping'
end

shop_path = '/tmp/zelda_checkpoints/shop_screen.marshal'
if File.exist?(shop_path)
  cpu3, ppu3, apu3, mmu3, = Zelda::Checkpoint.load(shop_path)
  puts "  shop_screen     room?=#{mmu3.read(0xFFF6)} map?=#{mmu3.read(0xFFF7)}"
end

house2_path = '/tmp/zelda_checkpoints/house2_interior.marshal'
if File.exist?(house2_path)
  cpu4, ppu4, apu4, mmu4, = Zelda::Checkpoint.load(house2_path)
  puts "  house2_interior room?=#{mmu4.read(0xFFF6)} map?=#{mmu4.read(0xFFF7)}"
end

overworld_screen2_path = '/tmp/zelda_checkpoints/overworld_screen2.marshal'
if File.exist?(overworld_screen2_path)
  cpu5, ppu5, apu5, mmu5, = Zelda::Checkpoint.load(overworld_screen2_path)
  puts "  overworld_screen2 room?=#{mmu5.read(0xFFF6)} map?=#{mmu5.read(0xFFF7)}"
end

front_yard_path = '/tmp/zelda_checkpoints/front_yard.marshal'
if File.exist?(front_yard_path)
  cpu6, ppu6, apu6, mmu6, = Zelda::Checkpoint.load(front_yard_path)
  puts "  front_yard      room?=#{mmu6.read(0xFFF6)} map?=#{mmu6.read(0xFFF7)}"
end
