# frozen_string_literal: true

require 'js'
require '/lib/driver'
require '/lib/utils/fps_counter'

RubyVM::YJIT.enable if defined?(RubyVM::YJIT)

ROM = JS.global[:gemboyRom].to_a.map(&:to_i)
LOADER = CartridgeLoader.from_bytes(ROM)
CARTRIDGE = LOADER.cartridge
DRIVER = Driver.build_from_cartridge(CARTRIDGE)

TARGET_GB_FPS = 59.7
DEBUG_UPDATE_INTERVAL = 30 # frames
NO_RENDER = JS.global[:gemboyNoRender] == JS::True

BUTTONS = {
  'ArrowUp' => :up,
  'ArrowDown' => :down,
  'ArrowLeft' => :left,
  'ArrowRight' => :right,
  'KeyZ' => :a,
  'KeyX' => :b,
  'Enter' => :start,
  'ShiftRight' => :select
}.freeze

canvas = JS.global[:document].getElementById('screen')
canvas.getContext('2d')[:imageSmoothingEnabled] = false
render = JS.global[:gemboyRender]

mode = DRIVER.motherboard.model.model_name.to_s.upcase
cart_type_byte = CARTRIDGE.rom_bytes[0x147]
rom_lines = [
  "Title: #{LOADER.name.delete("\0").strip}",
  format('Cart: %<summary>s (0x%<byte>02X)', summary: LOADER.cart_type_summary, byte: cart_type_byte),
  format('ROM: %<loaded>d/%<declared>d bytes (%<banks>d banks)', loaded: LOADER.rom_loaded_size,
                                                                 declared: LOADER.rom_declared_size,
                                                                 banks: LOADER.rom_bank_count),
  format('RAM: %<ram>d bytes', ram: LOADER.ram_size),
  "Mode: #{mode}#{' (no-render)' if NO_RENDER}"
]
JS.global[:gemboyRomInfo].apply(rom_lines.join("\n"))

fps_counter = FPSCounter.new
tick = 0
emulate_time_total = 0.0
render_time_total = 0.0

JS.global[:window].addEventListener('keydown') do |event|
  button = BUTTONS[event[:code].to_s]
  if button
    DRIVER.press(button)
    event.preventDefault
  end
end

JS.global[:window].addEventListener('keyup') do |event|
  button = BUTTONS[event[:code].to_s]
  if button
    DRIVER.release(button)
    event.preventDefault
  end
end

render_frame = lambda do
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  DRIVER.advance_frames(1)
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  unless NO_RENDER
    # Framebuffer pixels are packed with a leading 0xFF alpha byte, which overflows
    # wasm32 Ruby's Fixnum range and can't cross the JS bridge as-is.
    render.apply(DRIVER.framebuffer.map { |pixel| pixel & 0xFFFFFF }.to_js)
  end
  t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  emulate_time_total += t1 - t0
  render_time_total += t2 - t1
  tick += 1
  fps_counter.update
  next unless (tick % DEBUG_UPDATE_INTERVAL).zero?

  speed_ratio = fps_counter.last_fps / TARGET_GB_FPS
  avg_emulate_ms = (emulate_time_total / DEBUG_UPDATE_INTERVAL) * 1000
  avg_render_ms = (render_time_total / DEBUG_UPDATE_INTERVAL) * 1000
  emulate_time_total = 0.0
  render_time_total = 0.0

  JS.global[:gemboyDebug].apply([
    format('Speed: %<speed_ratio>.2fx  FPS: %<fps>d', speed_ratio:, fps: fps_counter.last_fps),
    format('Emulate: %<ms>.2f ms/frame', ms: avg_emulate_ms),
    format('Render:  %<ms>.2f ms/frame', ms: avg_render_ms),
    format('Frame: %<tick>d', tick:)
  ].join("\n"))
end

JS.global[:gemboyStatus].apply('playing')
JS.global[:setInterval].apply(-> { render_frame.call }, 16)
