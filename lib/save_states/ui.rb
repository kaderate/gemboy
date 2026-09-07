# frozen_string_literal: true

require_relative '../sdl_loader'
require_relative 'slots'

module SaveStates
  # Keyboard-facing side of the save states: turns key presses into requests for the emulation loop
  # to apply, and keeps the one-line status the screen overlays display.
  #
  # Pressed on the SDL thread, drained on the emulation thread: everything shared goes through the
  # request queue or a single string assignment.
  class UI
    DATE_FORMAT = '%d/%m %H:%M'
    DIGIT_SCANCODES = (SDL::SCANCODE_1..SDL::SCANCODE_9).to_a.freeze

    attr_reader :slot, :status, :slots

    def initialize(slots)
      @slots = slots
      @slot = Slots::NUMBERS.first
      @status = nil
      @requests = Thread::Queue.new
    end

    def key_pressed(scancode)
      case scancode
      when *DIGIT_SCANCODES then select_slot(DIGIT_SCANCODES.index(scancode) + 1)
      when SDL::SCANCODE_F5 then request(:save)
      when SDL::SCANCODE_F8 then request(:load)
      else return false
      end

      true
    end

    def pop_request
      @requests.pop(true)
    rescue ThreadError
      nil
    end

    def saved(slot) = report(slot, 'saved')
    def loaded(slot) = report(slot, 'loaded')
    def failed(slot, error) = report(slot, error.message)

    private

    def select_slot(slot)
      @slot = slot
      info = slots.info(slot)
      report(slot, info.exists? ? info.saved_at.strftime(DATE_FORMAT) : 'empty')
    end

    def request(action)
      @requests << [action, slot]
      report(slot, "#{action}...")
    end

    def report(slot, message) = @status = "Slot #{slot} · #{message}"
  end
end
