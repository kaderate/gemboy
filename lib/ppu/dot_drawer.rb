# frozen_string_literal: true

require_relative 'dot_drawer/base'
require_relative 'dot_drawer/cgb'
require_relative 'dot_drawer/dmg'

class PPU
  module DotDrawer
    COLOR_RGBA = [
      [0x9A, 0x9E, 0x3F, 0xFF],
      [0x49, 0x6B, 0x22, 0xFF],
      [0x0E, 0x45, 0x0B, 0xFF],
      [0x1B, 0x2A, 0x09, 0xFF]
    ].freeze
    # RGBA8888 on little-endian: SDL reads bytes [A,B,G,R] from memory as 0xRRGGBBAA
    COLOR_RGBA_SDL = COLOR_RGBA.map { |r, g, b, a| (a << 24) | (b << 16) | (g << 8) | r }.freeze

    def self.for_model(model, **)
      if model.cgb?
        CGB.new(**)
      else
        DMG.new(**)
      end
    end
  end
end
