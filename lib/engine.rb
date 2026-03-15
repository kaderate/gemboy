require 'ruby2d'

require_relative 'cpu'
require_relative 'rom_loader'

class Engine
  attr_accessor :cpu, :width, :height, :pixel_scale

  def initialize(rom_path)
    rom_bytes = RomLoader.new(rom_path).rom_bytes
    @cpu = CPU.new(rom_bytes)
    @pixel_scale = 2
    @width = 160
    @height = 144
    @title = "Game Boy Emulator"

    Ruby2D::Window.set width: @width * @pixel_scale, height: @height * @pixel_scale, title: @title

    Ruby2D::Window.update do
      run_cpu_step
      run_display_step
    end
  end

  def run
    Ruby2D::Window.show
  end

  private

  def run_cpu_step
    raise "CPU has stopped running" unless cpu.running?

    cpu.step

    # TODO: gérer les interruptions, timers, etc. ici
    # TODO: update la mémoire vidéo, les registres, etc. en fonction des instructions
  end

  def run_display_step
    color = hex_color_from_value(cpu.a)

    Ruby2D::Window.clear
    Ruby2D::Square.new(x: 0, y: 0, size: 160 * pixel_scale, color:)
  end

  def hex_color_from_value(value)
    r = (value * 16) % 256
    g = (value * 16) % 256
    b = (value * 16) % 256
    format("#%02x%02x%02x", r, g, b)
  end
end
