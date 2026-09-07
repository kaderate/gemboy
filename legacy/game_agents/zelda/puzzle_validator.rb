# frozen_string_literal: true
# Anti-cheat validator for the puzzle-solving spike (docs/ZELDA_AGENT.md).
#
# A hypothesis may only cite entity IDs that actually exist in the bounded packet. This is
# mechanical enforcement, not self-restraint: it doesn't stop pretrained knowledge from
# *influencing* which hypothesis gets ranked first, but it does catch the concrete failure mode
# of a hypothesis leaning on an item/mechanic that was never observed in this playthrough (e.g.
# "use the sword" when inventory.items_held is empty and no object called a sword exists).
#
# Usage: ruby zelda_puzzle_validator.rb <packet.json> <hypotheses.json>
require 'json'

packet_path, hyps_path = ARGV
packet = JSON.parse(File.read(packet_path, encoding: 'UTF-8'))
hypotheses = JSON.parse(File.read(hyps_path, encoding: 'UTF-8'))

known_ids = (packet['npcs'] || []).map { |n| n['id'] } +
            (packet['objects'] || []).map { |o| o['id'] } +
            (packet['inventory']['items_held'] || [])

# Common LA-lore item/mechanic names that must NEVER appear ungrounded -- if inventory or
# objects don't actually contain them, citing them is a strong signal the hypothesis leaned on
# outside knowledge of the game rather than the observed packet. Deliberately broad and easy to
# extend; false positives (a legitimate future in-packet object named similarly) are cheap to
# re-check by hand, false negatives (missing a real leak) are the expensive failure mode.
SUSPECT_TERMS = %w[
  épée sword bouclier shield bombe bomb palmes flippers bracelet grimpette
  ocarina plume feather sabot boots hameçon hook anneau ring coquillage
  seashell trident harpe harp
].freeze

held_terms = (packet['inventory']['items_held'] || []).join(' ').downcase
object_terms = (packet['objects'] || []).map { |o| o['id'].downcase }.join(' ')
grounded_terms = held_terms + ' ' + object_terms

results = hypotheses.map do |h|
  cited = h['cites'] || []
  unknown_citations = cited.reject { |id| known_ids.include?(id) }

  haystack = "#{h['action']} #{h['reasoning']}".downcase
  leaked_terms = SUSPECT_TERMS.select do |term|
    haystack.include?(term) && !grounded_terms.include?(term)
  end

  { id: h['hypothesis_id'], valid: unknown_citations.empty? && leaked_terms.empty?,
    unknown_citations: unknown_citations, leaked_terms: leaked_terms }
end

results.each do |r|
  status = r[:valid] ? 'VALID' : 'REJECTED'
  puts "#{r[:id]}: #{status}"
  puts "  unknown citations: #{r[:unknown_citations].join(', ')}" unless r[:unknown_citations].empty?
  puts "  leaked/ungrounded terms: #{r[:leaked_terms].join(', ')}" unless r[:leaked_terms].empty?
end

valid_count = results.count { |r| r[:valid] }
puts "\n#{valid_count}/#{results.size} hypotheses passed."
