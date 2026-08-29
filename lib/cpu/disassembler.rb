class CPU
  # Nommage lisible d'un opcode, utilisé uniquement pour les logs de debug.
  module Disassembler # rubocop:disable Metrics/ModuleLength
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def opcode_name(opcode)
      r8 = ->(i) { %w[B C D E H L (HL) A][i] }

      case opcode
      when 0x00 then 'NOP'
      when 0x76 then 'HALT'
      when 0x10 then 'STOP'

      # LD r8,d8
      when 0x06 then 'LD B,d8'
      when 0x0E then 'LD C,d8'
      when 0x16 then 'LD D,d8'
      when 0x1E then 'LD E,d8'
      when 0x26 then 'LD H,d8'
      when 0x2E then 'LD L,d8'
      when 0x36 then 'LD (HL),d8'
      when 0x3E then 'LD A,d8'

      # LD rr,d16
      when 0x01 then 'LD BC,d16'
      when 0x11 then 'LD DE,d16'
      when 0x21 then 'LD HL,d16'
      when 0x31 then 'LD SP,d16'
      when 0xF8 then 'LD HL,SP+r8'
      when 0xF9 then 'LD SP,HL'

      # LD r8,r8
      when 0x40..0x7F
        dst = r8.call((opcode - 0x40) / 8)
        src = r8.call((opcode - 0x40) % 8)
        "LD #{dst},#{src}"

      # LD (rr),A / LD A,(rr)
      when 0x02 then 'LD (BC),A'
      when 0x12 then 'LD (DE),A'
      when 0x22 then 'LDI (HL),A'
      when 0x32 then 'LDD (HL),A'
      when 0x0A then 'LD A,(BC)'
      when 0x1A then 'LD A,(DE)'
      when 0x2A then 'LDI A,(HL)'
      when 0x3A then 'LDD A,(HL)'
      when 0xEA then 'LD (a16),A'
      when 0xFA then 'LD A,(a16)'
      when 0x08 then 'LD (a16),SP'

      # INC r8
      when 0x04 then 'INC B'
      when 0x0C then 'INC C'
      when 0x14 then 'INC D'
      when 0x1C then 'INC E'
      when 0x24 then 'INC H'
      when 0x2C then 'INC L'
      when 0x34 then 'INC (HL)'
      when 0x3C then 'INC A'

      # DEC r8
      when 0x05 then 'DEC B'
      when 0x0D then 'DEC C'
      when 0x15 then 'DEC D'
      when 0x1D then 'DEC E'
      when 0x25 then 'DEC H'
      when 0x2D then 'DEC L'
      when 0x35 then 'DEC (HL)'
      when 0x3D then 'DEC A'

      # INC/DEC rr
      when 0x03 then 'INC BC'
      when 0x13 then 'INC DE'
      when 0x23 then 'INC HL'
      when 0x33 then 'INC SP'
      when 0x0B then 'DEC BC'
      when 0x1B then 'DEC DE'
      when 0x2B then 'DEC HL'
      when 0x3B then 'DEC SP'

      # ALU A,r8
      when 0x80..0x87 then "ADD A,#{r8.call(opcode - 0x80)}"
      when 0x88..0x8F then "ADC A,#{r8.call(opcode - 0x88)}"
      when 0x90..0x97 then "SUB A,#{r8.call(opcode - 0x90)}"
      when 0x98..0x9F then "SBC A,#{r8.call(opcode - 0x98)}"
      when 0xA0..0xA7 then "AND A,#{r8.call(opcode - 0xA0)}"
      when 0xA8..0xAF then "XOR A,#{r8.call(opcode - 0xA8)}"
      when 0xB0..0xB7 then "OR A,#{r8.call(opcode - 0xB0)}"
      when 0xB8..0xBF then "CP A,#{r8.call(opcode - 0xB8)}"

      # ALU A,d8
      when 0xC6 then 'ADD A,d8'
      when 0xCE then 'ADC A,d8'
      when 0xD6 then 'SUB A,d8'
      when 0xDE then 'SBC A,d8'
      when 0xE6 then 'AND A,d8'
      when 0xF6 then 'OR A,d8'
      when 0xFE then 'CP A,d8'

      # ADD HL,rr
      when 0x09 then 'ADD HL,BC'
      when 0x19 then 'ADD HL,DE'
      when 0x29 then 'ADD HL,HL'
      when 0x39 then 'ADD HL,SP'
      when 0xE8 then 'ADD SP,r8'

      # PUSH/POP
      when 0xC5 then 'PUSH BC'
      when 0xD5 then 'PUSH DE'
      when 0xE5 then 'PUSH HL'
      when 0xF5 then 'PUSH AF'
      when 0xC1 then 'POP BC'
      when 0xD1 then 'POP DE'
      when 0xE1 then 'POP HL'
      when 0xF1 then 'POP AF'

      # JP
      when 0xC3 then 'JP a16'
      when 0xC2 then 'JP NZ,a16'
      when 0xCA then 'JP Z,a16'
      when 0xD2 then 'JP NC,a16'
      when 0xDA then 'JP C,a16'
      when 0xE9 then 'JP HL'

      # JR
      when 0x18 then 'JR r8'
      when 0x20 then 'JR NZ,r8'
      when 0x28 then 'JR Z,r8'
      when 0x30 then 'JR NC,r8'
      when 0x38 then 'JR C,r8'

      # CALL
      when 0xCD then 'CALL a16'
      when 0xC4 then 'CALL NZ,a16'
      when 0xCC then 'CALL Z,a16'
      when 0xD4 then 'CALL NC,a16'
      when 0xDC then 'CALL C,a16'

      # RET
      when 0xC9 then 'RET'
      when 0xC0 then 'RET NZ'
      when 0xC8 then 'RET Z'
      when 0xD0 then 'RET NC'
      when 0xD8 then 'RET C'
      when 0xD9 then 'RETI'

      # RST
      when 0xC7 then 'RST 0x00'
      when 0xCF then 'RST 0x08'
      when 0xD7 then 'RST 0x10'
      when 0xDF then 'RST 0x18'
      when 0xE7 then 'RST 0x20'
      when 0xEF then 'RST 0x28'
      when 0xF7 then 'RST 0x30'
      when 0xFF then 'RST 0x38'

      # LDH
      when 0xE0 then 'LDH (a8),A'
      when 0xF0 then 'LDH A,(a8)'
      when 0xE2 then 'LDH (C),A'
      when 0xF2 then 'LDH A,(C)'

      # Interrupts
      when 0xF3 then 'DI'
      when 0xFB then 'EI'

      # Rotate A
      when 0x07 then 'RLCA'
      when 0x0F then 'RRCA'
      when 0x17 then 'RLA'
      when 0x1F then 'RRA'

      # CPL
      when 0x2F then 'CPL'

      # SCF/CCF
      when 0x37 then 'SCF'
      when 0x3F then 'CCF'

      # PREFIX CB
      when 0xCB then 'PREFIX CB'

      else "UNKNOWN ⚠️ (0x#{opcode.to_s(16).upcase})"
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  end
end
