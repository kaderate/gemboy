# frozen_string_literal: true

require 'fileutils'
require 'pathname'

require_relative '../save_states'
require_relative 'state'

module SaveStates
  # Maps the numbered save state slots of one cartridge onto files sitting next to its ROM.
  class Slots
    NUMBERS = (1..9)

    Info = Struct.new(:slot, :saved_at) do
      def exists? = !saved_at.nil?
    end

    attr_reader :cartridge

    def initialize(cartridge)
      @cartridge = cartridge
    end

    def path(slot)
      raise UnknownSlot, "slot #{slot} is outside #{NUMBERS}" unless NUMBERS.cover?(slot)

      Pathname.new(cartridge.rom_path).sub_ext(".s#{slot}").to_s
    end

    def save(slot, motherboard)
      bytes = State.dump(motherboard, cartridge)
      # Written aside then moved, so an interrupted save can't leave a half-written slot behind.
      tmp_path = "#{path(slot)}.tmp"
      File.binwrite(tmp_path, bytes)
      FileUtils.mv(tmp_path, path(slot))
    end

    def load(slot, logger: nil)
      raise EmptySlot, "slot #{slot} is empty" unless File.exist?(path(slot))

      State.load(File.binread(path(slot)), cartridge, logger:)
    end

    def info(slot)
      header_line = File.open(path(slot), 'rb') { |file| file.gets("\n") } if File.exist?(path(slot))
      saved_at = header_line && State.read_header(header_line)['saved_at']

      Info.new(slot, saved_at && Time.at(saved_at))
    rescue UnreadableState
      Info.new(slot, nil)
    end

    # Loading an older state overwrites the live cartridge RAM, and the next flush overwrites the
    # .sav with it. The backup is what makes the progress saved in-game since recoverable.
    def backup_battery_ram!
      battery_ram_path = cartridge.battery_ram_path
      FileUtils.cp(battery_ram_path, "#{battery_ram_path}.bak") if File.exist?(battery_ram_path || '')
    end
  end
end
