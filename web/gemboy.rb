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
canvas.getContext('2d')[:imageSmoothingEnabled] = false
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

JS.global[:gemboyStatus].call('playing')
JS.global[:setInterval].call(-> { render_frame.call }, 16)
