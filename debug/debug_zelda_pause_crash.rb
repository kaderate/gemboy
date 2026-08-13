# frozen_string_literal: true

require_relative 'headless_emulator'

input_sequence = [
  # [:key, :duration, label]
  [:wait, 3],
  [:start, 0.5, 'Skip intro, go to title screen'],
  [:wait],
  [:start, 0.5, 'Go to slot selection'],
  [:wait],
  [:start, 0.5, 'Select first slot'],
  [:wait],
  [:start, 0.5, 'Enter menu'],
  [:wait],
  [:start, 0.5, 'Exit menu => BOOM!'],
  [:wait]
].freeze
path = 'roms/zelda_dx_rev1.gbc'
screenshot_format = (ARGV[0] || 'image').to_sym

exit HeadlessEmulator.new(path:, input_sequence:, screenshot_format:).start
