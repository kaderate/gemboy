# frozen_string_literal: true

# ModelSelector holds the logic to select the model of the emulator (DMG, CGB)
class ModelSelector
  class NullModel
    def model_name = :dmg
    def cgb? = false
    def dmg? = true
  end

  attr_reader :model_name

  # Resolved eagerly: holding onto the cartridge would keep the ROM bytes alive in every object
  # graph the model is part of, save states included.
  def initialize(cartridge:, force_cgb: false)
    @model_name = case cartridge.cgb
                  when :only then :cgb
                  when :enhanced then force_cgb ? :cgb : :dmg
                  else :dmg
                  end
  end

  def cgb? = model_name == :cgb
  def dmg? = model_name == :dmg
end
