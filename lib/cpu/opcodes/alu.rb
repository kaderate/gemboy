class CPU
  module Opcodes
    # Arithmétique/logique 8 et 16 bits, y compris les rotations de A.
    module Alu # rubocop:disable Metrics/ModuleLength
      def op_dec_r8(opcode)
        reg_index = (opcode - 0x05) / 8
        new_value = (read_register_8(reg_index) - 1) & 0xFF
        write_register_8(reg_index, new_value)
        self.flag_z = new_value.zero?
        self.flag_h = new_value.allbits?(0xF)
        self.flag_n = true
        self.pc += 1
        4
      end

      def op_inc_r8(opcode)
        reg_index = (opcode - 0x04) / 8
        new_value = (read_register_8(reg_index) + 1) & 0xFF
        write_register_8(reg_index, new_value)
        self.flag_z = new_value.zero?
        self.flag_h = new_value.nobits?(0xF)
        self.flag_n = false
        self.pc += 1
        4
      end

      def op_inc_rr(opcode)
        reg_index = (opcode - 0x03) / 0x10
        value = (read_register_16(reg_index) + 1) & 0xFFFF
        write_register_16(reg_index, value)
        self.pc += 1
        8
      end

      def op_inc_dec_hl(opcode)
        sign = opcode == 0x34 ? 1 : -1
        original = read(hl)
        value = (original + sign) & 0xFF
        write(hl, value)

        self.flag_z = value.zero?
        self.flag_h = (original & 0xF) == (sign == 1 ? 0xF : 0)
        self.flag_n = sign == -1
        self.pc += 1
        12
      end

      def op_dec_rr(opcode)
        reg_index = (opcode - 0x0b) / 0x10
        value = (read_register_16(reg_index) - 1) & 0xFFFF
        write_register_16(reg_index, value)
        self.pc += 1
        8
      end

      def op_add_a_r8(opcode)
        reg_index = opcode - 0x80
        value = opcode == 0x86 ? read(hl) : read_register_8(reg_index)
        result = a + value
        self.flag_z = result.nobits?(0xFF)
        self.flag_n = false
        self.flag_h = ((a & 0xF) + (value & 0xF)) > 0xF
        self.flag_c = result > 0xFF
        self.a = result & 0xFF
        self.pc += 1
        opcode == 0x86 ? 8 : 4
      end

      def op_add_hl_rr(opcode)
        reg_index = (opcode - 0x09) / 0x10
        value = read_register_16(reg_index)
        result = hl + value
        self.flag_n = false
        self.flag_h = ((hl & 0xFFF) + (value & 0xFFF)) > 0xFFF
        self.flag_c = result > 0xFFFF
        self.hl = result & 0xFFFF
        self.pc += 1
        8
      end

      def op_add_sp_r8(_opcode)
        value = read(@pc + 1)
        value -= 256 if value > 127
        result = sp + value
        self.flag_z = false
        self.flag_n = false
        self.flag_h = ((sp & 0xF) + (value & 0xF)) > 0xF
        self.flag_c = ((sp & 0xFF) + (value & 0xFF)) > 0xFF
        self.sp = result
        self.pc += 2
        16
      end

      def op_sub_a_r8(opcode)
        reg_index = opcode - 0x90
        value = opcode == 0x96 ? read(hl) : read_register_8(reg_index)
        result = a - value
        self.flag_z = result.nobits?(0xFF)
        self.flag_n = true
        self.flag_h = (a & 0xF) < (value & 0xF)
        self.flag_c = a < value
        self.a = result & 0xFF
        self.pc += 1
        opcode == 0x96 ? 8 : 4
      end

      def op_adc_a_r8(opcode)
        reg_index = opcode - 0x88
        value = opcode == 0x8E ? read(hl) : read_register_8(reg_index)
        carry = flag_c ? 1 : 0
        result = a + value + carry
        self.flag_z = result.nobits?(0xFF)
        self.flag_n = false
        self.flag_h = ((a & 0xF) + (value & 0xF) + carry) > 0xF
        self.flag_c = result > 0xFF
        self.a = result & 0xFF
        self.pc += 1
        opcode == 0x8E ? 8 : 4
      end

      def op_add_a_d8(_opcode)
        value = read(@pc + 1)
        result = a + value
        self.flag_z = result.nobits?(0xFF)
        self.flag_n = false
        self.flag_h = ((a & 0xF) + (value & 0xF)) > 0xF
        self.flag_c = result > 0xFF
        self.a = result & 0xFF
        self.pc += 2
        8
      end

      def op_adc_a_d8(_opcode)
        value = read(@pc + 1)
        carry = flag_c ? 1 : 0
        result = a + value + carry
        self.flag_z = result.nobits?(0xFF)
        self.flag_n = false
        self.flag_h = ((a & 0xF) + (value & 0xF) + carry) > 0xF
        self.flag_c = result > 0xFF
        self.a = result & 0xFF
        self.pc += 2
        8
      end

      def op_sbc_a_r8(opcode)
        reg_index = opcode - 0x98
        value = opcode == 0x9E ? read(hl) : read_register_8(reg_index)
        carry = flag_c ? 1 : 0
        result = a - value - carry
        self.flag_z = result.nobits?(0xFF)
        self.flag_n = true
        self.flag_h = (a & 0xF) < ((value & 0xF) + carry)
        self.flag_c = a < (value + carry)
        self.a = result & 0xFF
        self.pc += 1
        opcode == 0x9E ? 8 : 4
      end

      def op_sub_a_d8(_opcode)
        value = read(@pc + 1)
        result = a - value
        self.flag_z = result.nobits?(0xFF)
        self.flag_n = true
        self.flag_h = (a & 0xF) < (value & 0xF)
        self.flag_c = a < value
        self.a = result & 0xFF
        self.pc += 2
        8
      end

      def op_sbc_a_d8(_opcode)
        value = read(@pc + 1)
        carry = flag_c ? 1 : 0
        result = a - value - carry
        self.flag_z = result.nobits?(0xFF)
        self.flag_n = true
        self.flag_h = (a & 0xF) < ((value & 0xF) + carry)
        self.flag_c = a < (value + carry)
        self.a = result & 0xFF
        self.pc += 2
        8
      end

      def op_daa(_opcode)
        if flag_n
          self.a -= 0x06 if flag_h
          self.a -= 0x60 if flag_c
        else
          initial_a = a
          new_a = a
          new_a += 0x06 if flag_h || (initial_a & 0x0F) > 0x09
          if flag_c || (initial_a > 0x99)
            new_a += 0x60
            self.flag_c = true
          end
          self.a = new_a
        end

        self.flag_z = (a == 0)
        self.flag_h = false

        self.pc += 1
        4
      end

      def op_and_a_r8(opcode)
        reg_index = opcode - 0xA0
        value = opcode == 0xA6 ? read(hl) : read_register_8(reg_index)
        self.a = a & value
        self.flag_z = (a == 0)
        self.flag_n = false
        self.flag_h = true
        self.flag_c = false
        self.pc += 1
        opcode == 0xA6 ? 8 : 4
      end

      def op_and_a_d8(_opcode)
        value = read(@pc + 1)
        self.a = a & value
        self.flag_z = (a == 0)
        self.flag_n = false
        self.flag_h = true
        self.flag_c = false
        self.pc += 2
        8
      end

      def op_or_a_r8(opcode)
        reg_index = opcode - 0xB0
        value = opcode == 0xB6 ? read(hl) : read_register_8(reg_index)
        self.a = a | value
        self.flag_z = (a == 0)
        self.flag_n = false
        self.flag_h = false
        self.flag_c = false
        self.pc += 1
        opcode == 0xB6 ? 8 : 4
      end

      def op_or_a_d8(_opcode)
        value = read(@pc + 1)
        self.a = a | value
        self.flag_z = (a == 0)
        self.flag_n = false
        self.flag_h = false
        self.flag_c = false
        self.pc += 2
        8
      end

      def op_xor_a_r8(opcode)
        reg_index = opcode - 0xA8
        value = opcode == 0xAE ? read(hl) : read_register_8(reg_index)
        self.a = a ^ value
        self.flag_z = (a == 0)
        self.flag_n = false
        self.flag_h = false
        self.flag_c = false
        self.pc += 1
        opcode == 0xAE ? 8 : 4
      end

      def op_xor_a_d8(_opcode)
        value = read(@pc + 1)
        self.a = a ^ value
        self.flag_z = (a == 0)
        self.flag_n = false
        self.flag_h = false
        self.flag_c = false
        self.pc += 2
        8
      end

      def op_cpl(_opcode)
        self.a = ~a
        self.flag_n = true
        self.flag_h = true
        self.pc += 1
        4
      end

      def op_scf(_opcode)
        self.flag_n = false
        self.flag_h = false
        self.flag_c = true
        self.pc += 1
        4
      end

      def op_ccf(_opcode)
        self.flag_n = false
        self.flag_h = false
        self.flag_c = !flag_c
        self.pc += 1
        4
      end

      def op_cp_a(opcode)
        reg_index = opcode - 0xB8
        value =
          if opcode == 0xFE
            read(@pc + 1)
          elsif opcode == 0xBE
            read(hl)
          else
            read_register_8(reg_index)
          end
        result = a - value
        self.flag_z = result.nobits?(0xFF)
        self.flag_n = true
        self.flag_h = (a & 0xF) < (value & 0xF)
        self.flag_c = a < value
        self.pc += opcode == 0xFE ? 2 : 1
        if opcode == 0xBE
          8
        else
          (opcode == 0xFE ? 8 : 4)
        end
      end

      def op_rotate_a(opcode)
        rotate_a_opcode(opcode)
        self.pc += 1
        4
      end

      def rotate_a_opcode(opcode)
        to_the_left = opcode & 0x08 == 0 # 0x07/0x17 vs 0x0F/0x1F
        with_carry = opcode & 0x10 != 0 # 0x17/0x1F vs 0x07/0x0F

        bit_to_rotate = to_the_left ? (a >> 7) : (a & 0x01)

        new_a = to_the_left ? (a << 1) : (a >> 1)
        new_a |=
          if with_carry
            if flag_c
              to_the_left ? 0x01 : 0x80
            else
              0
            end
          else # circular
            to_the_left ? bit_to_rotate : (bit_to_rotate << 7)
          end

        self.a = new_a & 0xFF
        self.flag_z = false
        self.flag_n = false
        self.flag_h = false
        self.flag_c = bit_to_rotate == 1
      end
    end
  end
end
