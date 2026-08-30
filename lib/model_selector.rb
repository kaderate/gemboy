# frozen_string_literal: true

# ModelSelector holds the logic to select the model of the emulator (DMG, CGB)
class ModelSelector
  class NullModel
    def model_name = :dmg
    def cgb? = false
    def dmg? = true
  end

  def initialize(cartridge:, force_cgb: false)
    @cartridge = cartridge
    @force_cgb = force_cgb
  end

  def model_name
    @model_name ||= if @cartridge.cgb == :only
                      :cgb
                    elsif @cartridge.cgb == :enhanced
                      (@force_cgb ? :cgb : :dmg)
                    else
                      :dmg
                    end
  end

  def cgb? = model_name == :cgb
  def dmg? = model_name == :dmg
end
