# frozen_string_literal: true

class MMU
  # Bypasses the PPU's bus gating for VRAM/OAM (see PPU::MemoryBus): real hardware blocks CPU
  # access during some modes and #read models that faithfully, answering 0xFF -- debug_read
  # answers what's actually stored regardless, same reasoning as Debug::Probes::PPUProbe.
  module Debug
    def debug_read(addr)
      case ADDR_TO_MEMORY_AREA[addr >> 8]
      when :vram then @ppu.vram.read(addr, bank: @ppu.vram_bus.bank)
      when :oam_or_empty then @ppu.oam.read(addr)
      else read(addr)
      end
    end
  end
end
