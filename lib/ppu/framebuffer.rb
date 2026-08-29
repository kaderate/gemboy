# frozen_string_literal: true

class PPU
  Framebuffer = Struct.new(:width, :height) do
    attr_reader :pixels

    def initialize(width, height)
      super
      @pixels = Array.new(height * width) { 0 }
    end

    def set_pixel(x, y, color)
      @pixels[(y * width) + x] = color
    end

    def set_pixels(color) = @pixels.fill(color)
    def get_pixel(x, y) = @pixels[(y * width) + x]
    def pixels_frame = @pixels.dup
  end
end
