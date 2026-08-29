class CPU
  module Opcodes
    # Instructions préfixées CB : rotations/shifts, swap, et test/set/reset de bit.
    module Cb
      def process_cb_opcode(cb_opcode)
        target = cb_opcode % 8

        case cb_opcode
        when 0x00..0x07 # RLC r8
          process_cb_rotate(target, direction: :left, mode: :circular)
        when 0x08..0x0F # RRC r8
          process_cb_rotate(target, direction: :right, mode: :circular)
        when 0x10..0x17 # RL r8
          process_cb_rotate(target, direction: :left, mode: :with_carry)
        when 0x18..0x1F # RR r8
          process_cb_rotate(target, direction: :right, mode: :with_carry)
        when 0x20..0x27 # SLA r8
          process_cb_rotate(target, direction: :left, mode: :arithmetic)
        when 0x28..0x2F # SRA r8
          process_cb_rotate(target, direction: :right, mode: :arithmetic)
        when 0x38..0x3F # SRL r8
          process_cb_rotate(target, direction: :right, mode: :logical)
        when 0x30..0x37 # SWAP r8
          process_swap(target)
        when 0x40..0x7F # BIT b,r8
          process_cb_bit_test(cb_opcode, target)
        when 0x80..0xBF # RES b,r8
          process_cb_bit_reset(cb_opcode, target)
        when 0xC0..0xFF # SET b,r8
          process_cb_bit_set(cb_opcode, target)
        else
          handle_unknown_opcode(0xCB00 | cb_opcode)
        end
      end

      def process_cb_rotate(target, direction:, mode:)
        old_value = read_cb_value(target)
        to_the_left = direction == :left

        bit_to_rotate = to_the_left ? (old_value >> 7) : (old_value & 0x01)

        new_value = to_the_left ? (old_value << 1) : (old_value >> 1)
        new_value |=
          case mode.to_sym
          when :circular
            to_the_left ? bit_to_rotate : (bit_to_rotate << 7)
          when :with_carry
            if flag_c
              to_the_left ? 0x01 : 0x80
            else
              0
            end
          when :arithmetic
            to_the_left ? 0 : (old_value & 0x80)
          when :logical
            0
          end

        new_flag_c = bit_to_rotate == 1
        write_cb_value_and_flags(target, new_value & 0xFF, new_flag_c:)
      end

      def process_swap(target)
        old_value = read_cb_value(target)
        new_value = ((old_value & 0x0F) << 4) | ((old_value & 0xF0) >> 4)

        write_cb_value_and_flags(target, new_value)
      end

      def process_cb_bit_test(cb_opcode, target)
        bit_index = (cb_opcode - 0x40) / 8
        value = read_cb_value(target)
        self.flag_z = value.nobits?(1 << bit_index)
        self.flag_n = false
        self.flag_h = true
        # C flag is unaffected

        cb_value_is_hl?(target) ? 12 : 8
      end

      def process_cb_bit_reset(cb_opcode, target)
        bit_index = (cb_opcode - 0x80) / 8
        value = read_cb_value(target)
        new_value = value & ~(1 << bit_index)
        write_cb_value(target, new_value)
      end

      def process_cb_bit_set(cb_opcode, target)
        bit_index = (cb_opcode - 0xC0) / 8
        value = read_cb_value(target)
        new_value = value | (1 << bit_index)
        write_cb_value(target, new_value)
      end

      def read_cb_value(target)
        cb_value_is_hl?(target) ? read(hl) : read_register_8(target)
      end

      def write_cb_value(target, value)
        if cb_value_is_hl?(target)
          write(hl, value)
        else
          write_register_8(target, value)
        end

        cb_value_is_hl?(target) ? 16 : 8
      end

      def write_cb_value_and_flags(target, value, new_flag_c: false)
        write_cb_value(target, value).tap do
          self.flag_z = value == 0
          self.flag_n = false
          self.flag_h = false
          self.flag_c = new_flag_c
        end
      end

      def cb_value_is_hl?(value)
        value == 6
      end
    end
  end
end
