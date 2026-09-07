# frozen_string_literal: true

require 'json'
require 'zlib'

require_relative '../motherboard'
require_relative '../save_states'

module SaveStates
  # Serializes a Motherboard into a self-describing byte string: a one-line JSON header followed by
  # the gzipped Marshal payload. The cartridge ROM stays out of the payload and is reattached from
  # the running cartridge on load.
  module State
    MAGIC = 'GEMBOY-STATE'
    # Marshal has no schema: bump this whenever a serialized class changes shape.
    FORMAT = 1

    class << self
      def dump(motherboard, cartridge)
        header = { magic: MAGIC, format: FORMAT, rom: cartridge.name, rom_sha256: cartridge.rom_sha256,
                   saved_at: Time.now.to_i }

        [JSON.generate(header), "\n", Zlib.gzip(motherboard.dump(with_rom: false))].map(&:b).join
      end

      def load(bytes, cartridge, logger: nil)
        header = read_header(bytes)
        raise IncompatibleVersion, "save state format #{header['format']}, expected #{FORMAT}" if header['format'] != FORMAT
        raise ROMMismatch, "save state was saved from #{header['rom']}" if header['rom_sha256'] != cartridge.rom_sha256

        payload = bytes.byteslice((bytes.index("\n") + 1)..)
        Motherboard.load(gunzip(payload), rom_bytes: cartridge.rom_bytes, logger:)
      end

      def read_header(bytes)
        line = bytes.byteslice(0, bytes.index("\n") || bytes.bytesize)
        header = JSON.parse(line)
        raise UnreadableState, 'not a Gemboy save state' unless header.is_a?(Hash) && header['magic'] == MAGIC

        header
      rescue JSON::ParserError
        raise UnreadableState, 'not a Gemboy save state'
      end

      private

      def gunzip(payload)
        Zlib.gunzip(payload)
      rescue Zlib::Error
        raise UnreadableState, 'corrupted save state payload'
      end
    end
  end
end
