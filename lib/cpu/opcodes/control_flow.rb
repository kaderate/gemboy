class CPU
  module Opcodes
    # Sauts, appels, retours, pile, et instructions divers un octet (NOP/HALT/STOP/DI/EI).
    module ControlFlow # rubocop:disable Metrics/ModuleLength
      def op_nop(_opcode)
        self.pc += 1
        4
      end

      def op_jp_a16(_opcode)
        self.pc = read_next_address
        16
      end

      def op_jp_nz_a16(_opcode)
        self.pc = flag_z ? (@pc + 3) : read_next_address
        flag_z ? 12 : 16
      end

      def op_jp_z_a16(_opcode)
        self.pc = flag_z ? read_next_address : (@pc + 3)
        flag_z ? 16 : 12
      end

      def op_jp_nc_a16(_opcode)
        self.pc = flag_c ? (@pc + 3) : read_next_address
        flag_c ? 12 : 16
      end

      def op_jp_c_a16(_opcode)
        self.pc = flag_c ? read_next_address : (@pc + 3)
        flag_c ? 16 : 12
      end

      def op_jp_hl(_opcode)
        self.pc = hl
        4
      end

      def op_di(_opcode)
        @ime = false
        self.pc += 1
        4
      end

      def op_ei(_opcode)
        # EI ne prend effet qu'après l'instruction suivante
        @pending_operations << -> { @ime = true }
        self.pc += 1
        4
      end

      def op_reti(_opcode)
        ret_opcode
        @ime = true
        16
      end

      def op_call_a16(_opcode)
        call_opcode(@pc + 3)
      end

      def op_call_nz_a16(_opcode)
        call_opcode(@pc + 3, condition: flag_z == false)
      end

      def op_call_z_a16(_opcode)
        call_opcode(@pc + 3, condition: flag_z)
      end

      def op_call_nc_a16(_opcode)
        call_opcode(@pc + 3, condition: flag_c == false)
      end

      def op_call_c_a16(_opcode)
        call_opcode(@pc + 3, condition: flag_c)
      end

      def op_ret(_opcode)
        ret_opcode
        16
      end

      def op_ret_nz(_opcode)
        ret_opcode(condition: !flag_z)
      end

      def op_ret_z(_opcode)
        ret_opcode(condition: flag_z)
      end

      def op_ret_nc(_opcode)
        ret_opcode(condition: !flag_c)
      end

      def op_ret_c(_opcode)
        ret_opcode(condition: flag_c)
      end

      def op_rst(opcode)
        target_address = (opcode - 0xC7)
        call_opcode(@pc + 1, target_address)
        16
      end

      def op_halt(_opcode)
        @logger&.debug { "HALT instruction encountered at #{@pc.to_s(16)}. Pausing CPU until an interrupt is served." }
        @halted[:value] = true
        @halted[:ime] = @ime
        self.pc += 1
        4
      end

      def op_stop(_opcode)
        if @speed_shift.armed
          @logger&.debug { "STOP instruction encountered at #{@pc.to_s(16)}, while speed shifter is armed. Switching speed." }
          @speed_shift.switch_speed!
        else
          @logger&.debug { "STOP instruction encountered at #{@pc.to_s(16)}. Pausing CPU until joypad is triggered." }
          @halted[:value] = true
          @halted[:stopped] = true
        end
        self.pc += 2
        0
      end

      def op_jr_nz_r8(_opcode)
        offset = read(@pc + 1)
        mem = if flag_z
                0
              else
                (offset < 128 ? offset : offset - 256)
              end
        self.pc += 2 + mem
        flag_z ? 8 : 12
      end

      def op_jr_z_r8(_opcode)
        offset = read(@pc + 1)
        mem = if flag_z
                offset < 128 ? offset : offset - 256
              else
                0
              end
        self.pc += 2 + mem
        flag_z ? 12 : 8
      end

      def op_jr_nc_r8(_opcode)
        offset = read(@pc + 1)
        mem = if flag_c
                0
              else
                (offset < 128 ? offset : offset - 256)
              end
        self.pc += 2 + mem
        flag_c ? 8 : 12
      end

      def op_jr_c_r8(_opcode)
        offset = read(@pc + 1)
        mem = if flag_c
                offset < 128 ? offset : offset - 256
              else
                0
              end
        self.pc += 2 + mem
        flag_c ? 12 : 8
      end

      def op_jr_r8(_opcode)
        offset = read(@pc + 1)
        if offset == 0xFE
          @infinite_loop = true
        else
          self.pc += 2 + (offset < 128 ? offset : offset - 256)
        end
        12
      end

      def op_push_rr(opcode)
        reg_index = (opcode - 0xC5) / 0x10
        value = read_register_16(reg_index)
        @sp = (@sp - 2) & 0xFFFF
        write_16(@sp, value)
        self.pc += 1
        16
      end

      def op_push_af(_opcode)
        value = (a << 8) | f
        @sp = (@sp - 2) & 0xFFFF
        write_16(@sp, value)
        self.pc += 1
        16
      end

      def op_pop_rr(opcode)
        reg_index = (opcode - 0xC1) / 0x10
        value = read_16(@sp)
        write_register_16(reg_index, value)
        @sp = (@sp + 2) & 0xFFFF
        self.pc += 1
        12
      end

      def op_pop_af(_opcode)
        self.af = read_16(@sp)
        @sp = (@sp + 2) & 0xFFFF
        self.pc += 1
        12
      end

      def op_prefix_cb(_opcode)
        cb_opcode = read(@pc + 1)
        nb_cycles = process_cb_opcode(cb_opcode)
        self.pc += 2
        nb_cycles
      end

      def op_unknown(opcode)
        handle_unknown_opcode(opcode)
      end
    end
  end
end
