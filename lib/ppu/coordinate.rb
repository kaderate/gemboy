# frozen_string_literal: true

class PPU
  # Coordinates are used to address pixels in the framebuffer and in sprites
  module Coordinate
    def self.flip(value, flipped, base = 8) = flipped ? (base - 1 - value) : value
  end
end
