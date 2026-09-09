# frozen_string_literal: true

require_relative 'cartridge_loader'
require_relative 'fake_keys'
require_relative 'motherboard'

# Headless entry point for driving a Gameboy programmatically (D6): frame advancing, key input,
# memory reads and in-memory snapshot/restore over a Motherboard, without SDL.
class Session
  FRAME_CYCLES = 70_224

  attr_reader :motherboard

  def self.build(rom_path, force_cgb: false)
    cartridge = CartridgeLoader.new(rom_path).cartridge
    motherboard = Motherboard.build(cartridge, force_cgb:)
    motherboard.mmu.joypad.key_state = FakeKeys.new
    new(motherboard)
  end

  def self.restore(bytes) = new(Motherboard.load(bytes))

  def initialize(motherboard)
    @motherboard = motherboard
  end

  def press(*buttons) = buttons.each { |button| key_state.press(button) }
  def release(*buttons) = buttons.each { |button| key_state.send("#{button}=", false) }
  def clear_keys = key_state.clear

  def tap(*buttons, hold_frames: 2, settle_frames: 28)
    press(*buttons)
    advance_frames(hold_frames)
    release(*buttons)
    advance_frames(settle_frames)
  end

  def advance_cycles(target_cycles) = motherboard.run_cycles(target_cycles)
  def advance_frames(count) = advance_cycles(count * FRAME_CYCLES)

  def read(addr) = motherboard.mmu.read(addr)
  def debug_read(addr) = motherboard.mmu.debug_read(addr)

  def framebuffer_png(path) = motherboard.ppu.export_framebuffer_png(path)

  def snapshot = motherboard.dump

  private

  def key_state = motherboard.mmu.joypad.key_state
end
