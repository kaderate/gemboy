# frozen_string_literal: true

# Replays dmg_sound/01-registers' `test_rw` against the MMU: writes every value to every APU
# register and checks the read-back equals `value | mask`. Prints one line per register.
#
# The mask table is transcribed from Blargg's source on purpose -- reading it from MMU::READ_MASKS
# would make the check tautological.
#
# Usage: ruby apu_readback.rb

require_relative 'spec/support/builders'

module APUReadback
  extend Builders

  MASKS = [
    0x80, 0x3F, 0x00, 0xFF, 0xBF, # NR10-NR14  FF10-FF14
    0xFF, 0x3F, 0x00, 0xFF, 0xBF, # NR20-NR24  FF15-FF19
    0x7F, 0xFF, 0x9F, 0xFF, 0xBF, # NR30-NR34  FF1A-FF1E
    0xFF, 0xFF, 0x00, 0x00, 0xBF, # NR40-NR44  FF1F-FF23
    0x00, 0x00, 0x70,             # NR50-NR52  FF24-FF26
    *([0xFF] * 9),                # unused     FF27-FF2F
    *([0x00] * 16)                # wave RAM   FF30-FF3F
  ].freeze

  BASE = 0xFF10
  NR52 = 0xFF26 # skipped by test_rw, covered by its own sub-test
  NAMES = (%w[NR10 NR11 NR12 NR13 NR14 NR20 NR21 NR22 NR23 NR24 NR30 NR31 NR32 NR33 NR34
              NR40 NR41 NR42 NR43 NR44 NR50 NR51 NR52] +
           (0x27..0x2F).map { format('--%<low>02X', low: _1) } +
           (0..15).map { format('WAV%<index>X', index: _1) }).freeze

  def self.run
    fails = measure
    report(fails)
  end

  def self.measure
    mmu = build_mmu
    mmu.write(NR52, 0x80) # APU on
    fails = Hash.new { |h, k| h[k] = [] }

    256.times do |value|
      MASKS.each_with_index do |mask, index|
        addr = BASE + index
        next if addr == NR52

        mmu.write(addr, value)
        got = mmu.read(addr)
        fails[addr] << [value, mask | value, got] if got != (mask | value)

        mmu.write(0xFF25, 0) # wreg NR51,0 -- mute, as test_rw does
        mmu.write(0xFF1A, 0) # wreg NR30,0 -- disable wave
      end
    end

    fails
  end

  def self.report(fails)
    puts 'addr   reg    mask   échecs    premier écart (valeur -> attendu / lu)'
    puts '-' * 74

    MASKS.each_with_index { |mask, index| puts line_for(fails, mask, index) unless BASE + index == NR52 }

    total = fails.values.sum(&:size)
    passes = 256 * 47
    puts '-' * 74
    puts "total : #{total} / #{passes} passes en échec (#{(100.0 * total / passes).round(1)} %)"
    puts "registres fautifs : #{fails.count { |_, v| v.any? }} / 47"
  end

  def self.line_for(fails, mask, index)
    addr = BASE + index
    misses = fails[addr]
    detail = misses.empty? ? '' : format('%<v>02X -> %<want>02X / %<got>02X', *%i[v want got].zip(misses.first).to_h)

    format('$%<addr>04X  %<reg>-6s $%<mask>02X    %<count>-9s %<detail>s',
           addr:, reg: NAMES[index], mask:,
           count: misses.empty? ? 'ok' : format('%<n>3d/256', n: misses.size), detail:)
  end
end

APUReadback.run
