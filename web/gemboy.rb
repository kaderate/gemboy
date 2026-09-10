# frozen_string_literal: true

require 'js'
require '/lib/driver'

ROM = JS.global[:gemboyRom].to_a.map(&:to_i)
DRIVER = Driver.build_from_bytes(ROM)

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
context = canvas.getContext('2d')
context[:imageSmoothingEnabled] = false
image_data = JS.global[:ImageData].new(160, 144)
render = JS.global[:gemboyRender]

JS.global[:window].addEventListener('keydown') do |event|
  button = BUTTONS[event[:code].to_s]
  DRIVER.press(button) if button
  event.preventDefault if button
end

JS.global[:window].addEventListener('keyup') do |event|
  button = BUTTONS[event[:code].to_s]
  DRIVER.release(button) if button
  event.preventDefault if button
end

render_frame = lambda do
  DRIVER.advance_frames(1)
  render.call(DRIVER.framebuffer.to_js)
end

JS.global[:gemboyStatus].call(:replace, 'playing')
JS.global[:requestAnimationFrame].call(->(_timestamp) { render_frame.call })
JS.global[:setInterval].call(-> { render_frame.call }, 16)
