# frozen_string_literal: true

# Question falsifiable (revue ZELDA_ARCHITECTURE_REVIEW.md, plan recommande #1) :
# la position de Link et l'ID de salle sont-ils lisibles en HRAM aux adresses hypothesees
# (hLinkPositionX ~$FF98, hLinkPositionY ~$FF99, direction ~$FF9E, hMapRoom ~$FFF6, map id ~$FFF7) ?
# Budget : diff complet 0x0000-0xFFFF autour de 4 appuis dans une meme direction, sur 2 directions
# orthogonales (RIGHT puis DOWN) pour croiser le signe. Livrable : ram_registry.json mis a jour
# (verified ou refuted) avec la preuve.
$LOAD_PATH.unshift(File.expand_path('/home/user/gemboy/lib'))
$LOAD_PATH.unshift(File.expand_path('/home/user/gemboy/profiling'))
require 'utils'
require_relative '/home/user/gemboy/lib/game_agents/zelda/checkpoint'

CANDIDATES = {
  'hLinkPositionX?' => 0xFF98,
  'hLinkPositionY?' => 0xFF99,
  'hLinkDirection?' => 0xFF9E,
  'hMapRoom?' => 0xFFF6,
  'hMapId?' => 0xFFF7
}.freeze

def dump_all(mmu)
  Array.new(0x10000) { |addr| mmu.read(addr) }
end

def tap_dir(cpu, ppu, apu, mmu, keys, dir)
  keys.press(dir)
  run_steps(cpu, ppu, apu, 20_000)
  keys.clear
  run_steps(cpu, ppu, apu, 20_000)
end

checkpoint_path = '/tmp/zelda_checkpoints/villager_screen.marshal'
raise "checkpoint missing: #{checkpoint_path}" unless File.exist?(checkpoint_path)

cpu, ppu, apu, mmu, keys = Zelda::Checkpoint.load(checkpoint_path)

puts '=== direct check of hypothesized addresses ==='
before = dump_all(mmu)
CANDIDATES.each { |name, addr| puts format('%-18s $%04X = %3d (0x%02X)', name, addr, before[addr], before[addr]) }

puts "\n=== RIGHT x4, one tap at a time, watching hypothesized addrs ==="
4.times do |i|
  tap_dir(cpu, ppu, apu, mmu, keys, :right)
  now = dump_all(mmu)
  CANDIDATES.each do |name, addr|
    delta = now[addr] - before[addr]
    puts format('  tap %d %-18s $%04X = %3d (delta %+d)', i + 1, name, addr, now[addr], delta) if delta != 0
  end
  before = now
end

puts "\n=== full-space diff after RIGHT vs after DOWN (small consistent delta hunt) ==="
cpu2, ppu2, apu2, mmu2, keys2 = Zelda::Checkpoint.load(checkpoint_path)
base = dump_all(mmu2)

right_deltas = Array.new(4)
4.times do |i|
  tap_dir(cpu2, ppu2, apu2, mmu2, keys2, :right)
  snap = dump_all(mmu2)
  right_deltas[i] = (0...0x10000).each_with_object({}) { |a, h| d = snap[a] - base[a]; h[a] = d if d != 0 }
  base = snap
end

common_right = right_deltas[0].keys
right_deltas[1..].each { |h| common_right &= h.keys }
consistent_sign_right = common_right.select do |a|
  signs = right_deltas.map { |h| h[a] <=> 0 }
  signs.uniq.size == 1 && signs.first != 0 && right_deltas.all? { |h| h[a].abs <= 20 }
end

puts "addresses with small same-signed delta on all 4 RIGHT taps: #{consistent_sign_right.size}"
consistent_sign_right.sort.each do |a|
  deltas = right_deltas.map { |h| h[a] }
  region = case a
           when 0x8000..0x9FFF then 'VRAM'
           when 0xA000..0xBFFF then 'ExtRAM'
           when 0xC000..0xDFFF then 'WRAM'
           when 0xFE00..0xFE9F then 'OAM'
           when 0xFF00..0xFF7F then 'IO'
           when 0xFF80..0xFFFE then 'HRAM'
           else 'other'
           end
  puts format('  $%04X [%s] deltas=%p', a, region, deltas)
end

cpu3, ppu3, apu3, mmu3, keys3 = Zelda::Checkpoint.load(checkpoint_path)
base3 = dump_all(mmu3)
down_deltas = Array.new(4)
4.times do |i|
  tap_dir(cpu3, ppu3, apu3, mmu3, keys3, :down)
  snap = dump_all(mmu3)
  down_deltas[i] = (0...0x10000).each_with_object({}) { |a, h| d = snap[a] - base3[a]; h[a] = d if d != 0 }
  base3 = snap
end

puts "\n=== cross-check: RIGHT-consistent addresses, do they flip sign or go flat on DOWN? ==="
consistent_sign_right.sort.each do |a|
  right_sign = right_deltas.map { |h| h[a] <=> 0 }.first
  down_vals = down_deltas.map { |h| h[a] || 0 }
  down_sign = down_vals.map { |v| v <=> 0 }.uniq
  puts format('  $%04X right_sign=%+d down_deltas=%p', a, right_sign, down_vals)
end
