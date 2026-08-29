# frozen_string_literal: true

class PPU
  class Mode
    REGULAR_SCANLINES = 0...144
    VBLANK_SCANLINES = 144...Scanline::TOTAL_SCANLINES

    MODE_2_CYCLES = 0...80
    MODE_3_CYCLES = 80...252
    MODE_0_CYCLES = 252...CYCLES_PER_SCANLINE
    MODES = {
      mode_2: 2, # OAM Scan
      mode_3: 3, # Pixel Transfer
      mode_0: 0, # Mode 0 (HBlank) est considéré comme le mode "normal" où le PPU est prêt à dessiner la prochaine ligne
      vblank: 1  # VBlank est un mode spécial où le PPU pause pour laisser le CPU bosser sans interférer avec l'écran
    }.freeze

    attr_accessor :name

    # @name starts nil (not :mode_0) on purpose: forces the very first #tick through the full loop (not the fast path), who set
    # the real state before anything trusts it.
    def mode_index = MODES[name] || 0

    # cycles/scanline_value are the PPU's own clock, not owned here (see #cycles_until_next_mode_change).
    def update!(ly, cycles)
      old_name = name
      self.name = case ly
                  when REGULAR_SCANLINES
                    case cycles
                    when MODE_2_CYCLES then :mode_2
                    when MODE_3_CYCLES then :mode_3
                    when MODE_0_CYCLES then :mode_0
                    end
                  when VBLANK_SCANLINES then :vblank
                  end

      old_name != name
    end

    def cycles_until_next_mode_change(cycles)
      case name
      when :mode_2 then MODE_2_CYCLES.end - cycles
      when :mode_3 then MODE_3_CYCLES.end - cycles
      when :mode_0 then MODE_0_CYCLES.end - cycles
      when :vblank then CYCLES_PER_SCANLINE - cycles
      else 0
      end
    end
  end
end
