# frozen_string_literal: true

# Records the PCM output of a ROM and compares it to a stored baseline. The only net that catches
# "the sound changed subtly": neither the specs nor the test ROMs look at the mixed samples.
#
# A mismatch is not always a regression -- a refactor that moves when register writes take effect
# will legitimately shift the output. The point is to know exactly when and where it moved.
#
# Usage: ruby debug/audio_golden_master.rb <record|check> [rom] [steps]

require_relative '../profiling/utils'
require 'digest'
require 'fileutils'

module AudioGoldenMaster
  BASELINE_DIR = 'tmp/golden'
  DEFAULT_ROM = 'roms/tetris_world_rev1.gb'
  DEFAULT_STEPS = 5_000_000
  # Enough context to locate a divergence without dumping the whole track
  PREVIEW = 4

  def self.run(argv)
    mode = argv[0] || 'check'
    rom = argv[1] || DEFAULT_ROM
    steps = (argv[2] || DEFAULT_STEPS).to_i

    samples = capture(rom, steps)
    case mode
    when 'record' then record(rom, steps, samples)
    when 'check' then check(rom, steps, samples)
    else abort "Usage: #{$PROGRAM_NAME} <record|check> [rom] [steps]"
    end
  end

  def self.capture(rom, steps)
    cpu, ppu, apu, mmu = build_emulator(rom)
    mmu.attach_apu(apu)
    run_steps(cpu, ppu, apu, steps)

    samples = []
    samples << apu.audio_queue.pop until apu.audio_queue.empty?
    samples
  end

  def self.baseline_path(rom, steps)
    File.join(BASELINE_DIR, "#{File.basename(rom, '.gb').gsub(/\W+/, '_')}-#{steps}.txt")
  end

  def self.record(rom, steps, samples)
    FileUtils.mkdir_p(BASELINE_DIR)
    path = baseline_path(rom, steps)
    File.write(path, serialize(samples))

    puts "baseline écrite : #{path}"
    puts summary(samples)
  end

  def self.check(rom, steps, samples)
    path = baseline_path(rom, steps)
    abort "pas de baseline : lance d'abord `#{$PROGRAM_NAME} record #{rom} #{steps}`" unless File.exist?(path)

    expected = File.read(path).lines.map(&:chomp)
    got = serialize(samples).lines.map(&:chomp)

    puts summary(samples)
    return puts "IDENTIQUE à #{path}" if expected == got

    report_divergence(expected, got, path)
    exit 1
  end

  def self.report_divergence(expected, got, path)
    index = expected.zip(got).index { |a, b| a != b } || [expected.size, got.size].min
    differing = expected.zip(got).count { |a, b| a != b }

    puts "DIFFÈRE de #{path}"
    puts "  taille        : #{expected.size} attendus, #{got.size} obtenus"
    puts "  premier écart : échantillon #{index} (#{format('%.3f', index / SAMPLES_PER_SECOND)} s de son émis)"
    puts "  échantillons différents : #{differing}"
    puts
    window = ([index - PREVIEW, 0].max...(index + PREVIEW))
    puts '  index    attendu                obtenu'
    window.each do |i|
      puts format('  %<i>-8d %<expected>-22s %<got>s', i:, expected: expected[i].inspect, got: got[i].inspect)
    end
  end

  # The mixer emits one sample per audio frame, both channels at once
  SAMPLES_PER_SECOND = AudioSampler::SOUND_SAMPLE_RATE_HZ

  def self.serialize(samples)
    samples.map { |s| Array(s).map { |v| format('%.6f', v) }.join(' ') }.join("\n")
  end

  def self.summary(samples)
    flat = samples.flatten
    non_zero = flat.count { _1 != 0 }
    format('%<count>d échantillons, %<non_zero>d non nuls (%<ratio>.1f %%), min %<min>.3f max %<max>.3f, sha %<sha>s',
           count: samples.size, non_zero:, ratio: 100.0 * non_zero / flat.size,
           min: flat.min, max: flat.max, sha: Digest::SHA256.hexdigest(serialize(samples))[0, 12])
  end
end

AudioGoldenMaster.run(ARGV)
