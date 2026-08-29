class CPU
  module Opcodes
    # Instructions LD/LDH/LDI/LDD : transferts entre registres, mémoire et immédiats.
    module Loads # rubocop:disable Metrics/ModuleLength
      def op_ld_r8_d8(opcode)
        reg_index = (opcode - 0x06) / 8
        write_register_8(reg_index, read(@pc + 1))
        self.pc += 2
        8
      end

      def op_ld_hl_d8(_opcode)
        write(hl, read(@pc + 1))
        self.pc += 2
        12
      end

      def op_ld_r8_r8(opcode)
        dest_index = (opcode - 0x40) / 8
        src_index = (opcode - 0x40) % 8

        value = src_index == 6 ? read(hl) : read_register_8(src_index) # LD r8,(HL)

        if dest_index == 6 # LD (HL),r8
          write(hl, value)
        else
          write_register_8(dest_index, value)
        end

        self.pc += 1
        src_index == 6 || dest_index == 6 ? 8 : 4
      end

      def op_ld_rr_d16(opcode)
        reg_index = (opcode - 0x01) / 0x10
        write_register_16(reg_index, read_next_address)
        self.pc += 3
        12
      end

      def op_ld_hl_sp_r8(_opcode)
        value = read(@pc + 1)
        value -= 256 if value > 127
        result = sp + value
        self.flag_z = false
        self.flag_n = false
        self.flag_h = ((sp & 0xF) + (value & 0xF)) > 0xF
        self.flag_c = ((sp & 0xFF) + (value & 0xFF)) > 0xFF
        self.hl = result
        self.pc += 2
        12
      end

      def op_ld_sp_hl(_opcode)
        self.sp = hl
        self.pc += 1
        8
      end

      def op_ld_bc_a(_opcode)
        write(bc, a)
        self.pc += 1
        8
      end

      def op_ld_de_a(_opcode)
        write(de, a)
        self.pc += 1
        8
      end

      def op_ldi_hl_a(_opcode)
        write(hl, a)
        self.hl = (hl + 1) & 0xFFFF
        self.pc += 1
        8
      end

      def op_ldd_hl_a(_opcode)
        write(hl, a)
        self.hl = (hl - 1) & 0xFFFF
        self.pc += 1
        8
      end

      def op_ld_a_bc(_opcode)
        self.a = read(bc)
        self.pc += 1
        8
      end

      def op_ld_a_de(_opcode)
        self.a = read(de)
        self.pc += 1
        8
      end

      def op_ldi_a_hl(_opcode)
        self.a = read(hl)
        self.hl = (hl + 1) & 0xFFFF
        self.pc += 1
        8
      end

      def op_ldd_a_hl(_opcode)
        self.a = read(hl)
        self.hl = (hl - 1) & 0xFFFF
        self.pc += 1
        8
      end

      def op_ld_a16_sp(_opcode)
        address = read_next_address
        write(address, sp & 0xFF)
        write(address + 1, (sp >> 8) & 0xFF)
        self.pc += 3
        20
      end

      def op_ld_a16_a(_opcode)
        address = read_next_address
        write(address, a)
        self.pc += 3
        16
      end

      def op_ld_a_a16(_opcode)
        address = read_next_address
        self.a = read(address)
        self.pc += 3
        16
      end

      def op_ldh_a8_a(_opcode)
        address = 0xFF00 + read(@pc + 1)
        write(address, a)
        self.pc += 2
        12
      end

      def op_ldh_a_a8(_opcode)
        address = 0xFF00 + read(@pc + 1)
        self.a = read(address)
        self.pc += 2
        12
      end

      def op_ldh_c_a(_opcode)
        address = 0xFF00 + c
        write(address, a)
        self.pc += 1
        8
      end

      def op_ldh_a_c(_opcode)
        address = 0xFF00 + c
        self.a = read(address)
        self.pc += 1
        8
      end
    end
  end
end
