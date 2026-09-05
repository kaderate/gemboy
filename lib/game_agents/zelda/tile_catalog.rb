# frozen_string_literal: true

require 'json'

# Persistent, cumulative catalog of BG tile classifications, keyed by TilemapReader's
# pattern_hash (stable across screens/VRAM banks -- see tilemap_reader.rb). The premise this
# exploits: a background tile never changes what it *is* over the course of the game (grass is
# always grass, a wall is always a wall -- see ZELDA_BACKLOG.md's navigation overhaul writeup), so
# once a tile is classified here it never needs re-testing on any future screen. That's the whole
# point versus RoomMap::Recorder's per-screen empirical rediscovery: the number of `unknown` tiles
# on a new screen should trend toward zero as the catalog grows.
#
# `passable_from` records confirmed ENTRY directions only (never inferred as symmetric) -- this is
# how an asymmetric obstacle (e.g. a ledge you can leap down but not climb back up, confirmed in
# the game's own manual as a basic, itemless move -- see ZELDA_BACKLOG.md) is represented: its
# passable_from might be `["down"]` while `["up"]` stays untested or confirmed blocked separately.
# An empty passable_from does NOT necessarily mean "wall forever" -- `requires_item` captures the
# manual's own note that water is crossed automatically once Flippers are obtained, implying it's
# likely a hard block before that (a hypothesis, not yet confirmed on this save file).
module Zelda
  class TileCatalog
    CATEGORIES = %i[walkable wall water ledge hole door decorative unknown].freeze
    DIRECTIONS = %i[up down left right].freeze

    Entry = Struct.new(:category, :passable_from, :confidence, :source, :first_seen, :requires_item,
                       :note, keyword_init: true) do
      def to_h
        { category:, passable_from: passable_from.to_a, confidence:, source:, first_seen:, requires_item:, note: }
      end
    end

    def initialize
      @entries = {} # pattern_hash => Entry
    end

    def self.load(path)
      catalog = new
      return catalog unless File.exist?(path)

      JSON.parse(File.read(path, encoding: 'UTF-8')).each do |hash, data|
        catalog.instance_variable_get(:@entries)[hash] = Entry.new(
          category: data['category'].to_sym,
          passable_from: data['passable_from'].to_set(&:to_sym),
          confidence: data['confidence'].to_sym,
          source: data['source'],
          first_seen: data['first_seen'],
          requires_item: data['requires_item'],
          note: data['note']
        )
      end
      catalog
    end

    def save(path)
      File.write(path, JSON.pretty_generate(@entries.transform_values(&:to_h)))
    end

    def lookup(hash) = @entries[hash]

    # A tile only counts as "known" once it has a real category, not just a partial
    # record_passable! probe result still sitting at the default :unknown category.
    def known?(hash) = @entries.key?(hash) && @entries[hash].category != :unknown

    # Records or refines a classification. Merges passable_from with whatever was already known
    # (a new confirmed direction adds to the set, it never removes a previously confirmed one).
    def classify!(hash, category:, source:, confidence: :hypothesis, passable_from: [], requires_item: nil,
                  first_seen: nil, note: nil)
      raise ArgumentError, "unknown category #{category}" unless CATEGORIES.include?(category)

      existing = @entries[hash]
      merged_passable = (existing&.passable_from || Set.new) | passable_from
      @entries[hash] = Entry.new(
        category:, source:, confidence:, requires_item:,
        passable_from: merged_passable,
        first_seen: existing&.first_seen || first_seen,
        note: note || existing&.note
      )
    end

    # Records one confirmed entry direction for an already (or newly, as :unknown) tracked tile,
    # without committing to a final category yet -- used by the targeted classifier while it's
    # still probing a new tile's other directions.
    def record_passable!(hash, direction, category: :unknown, source: 'empirique', first_seen: nil)
      existing = @entries[hash]
      classify!(hash, category: existing&.category || category, source:,
                      confidence: existing&.confidence || :hypothesis,
                      passable_from: [direction], first_seen:)
    end

    # Pattern hashes present in `grid` (see TilemapReader.visible_grid) that aren't in the catalog
    # yet -- what a classifier still needs to look at on this screen.
    def unknown_in(grid)
      grid.map(&:pattern_hash).uniq.reject { |hash| known?(hash) }
    end

    def size = @entries.size
  end
end
