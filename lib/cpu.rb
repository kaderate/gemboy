# GameBoy DMG-01 CPU Emulator en Ruby
class CPU
  ADDR_LCDC = 0xFF40
  ADDR_INP1 = 0xFF00
  ROM_RANGE = 0x0000..0x7FFF
  VRAM_RANGE = 0x8000..0x9FFF
  WRAM_RANGE = 0xC000..0xDFFF
  IO_RANGE = 0xFF01..0xFF7F # Exclut ADDR_INP1
  HRAM_RANGE = 0xFF80..0xFFFE

  REGS_8 = [:b, :c, :d, :e, :h, :l, nil, :a]
  REGS_16 = [:bc, :de, :hl, :sp]

  attr_accessor :a, :f
  attr_reader :pc, :sp, :b, :c, :d, :e, :h, :l, :key_state

  def initialize(rom_bytes)
    @rom = rom_bytes
    @vram = Array.new(0x2000, 0) # 8KB de VRAM
    @wram = Array.new(0x2000, 0) # 8KB de WRAM
    @io = Array.new(0x80, 0)     # 128 octets d'I/O
    @hram = Array.new(0x7F, 0)   # 127 octets de HRAM
    @key_state = nil
    @inputs_selector = nil # nil, :direction, ou :button

    @infinite_loop = false
    @running = true

    # Registres spéciaux
    @pc = 0x100  # point d'entrée standard des ROMs GB
    @sp = 0xFFFE # pile initiale

    # Registres généraux
    @a = @f = @b = @c = @d = @e = @h = @l = 0

    # Flags
    flags.keys.each do |flag|
      define_singleton_method("flag_#{flag}") do
        flags[flag]
      end

      define_singleton_method("flag_#{flag}=") do |value|
        if value
          @f |= (0x80 >> flags.keys.index(flag)) # Set the flag bit
        else
          @f &= ~(0x80 >> flags.keys.index(flag)) # Clear the flag bit
        end
      end
    end
  end

  def set_key_state(key_state)
    @key_state = key_state
  end

  def flags
    {
      z: (@f & 0x80) != 0, # Zero flag
      n: (@f & 0x40) != 0, # Subtract flag
      h: (@f & 0x20) != 0, # Half Carry flag
      c: (@f & 0x10) != 0  # Carry flag
    }
  end

  def lcd_control
    x = read(ADDR_LCDC)
    {
      lcd_enable: (x & 0x80) != 0,
      window_tile_map_display_select: (x & 0x40) != 0,
      window_display_enable: (x & 0x20) != 0,
      bg_and_window_tile_data_select: (x & 0x10) != 0,
      bg_tile_map_display_select: (x & 0x08) != 0,
      obj_size: (x & 0x04) != 0,
      obj_display_enable: (x & 0x02) != 0,
      bg_display: (x & 0x01) != 0
    }
  end

  def af
    (@a << 8) | @f
  end

  def af=(value)
    @a = (value >> 8) & 0xFF
    @f = value & 0xF0 # les 4 bits de poids faible de F sont toujours 0
  end

  def bc
    (@b << 8) | @c
  end

  def bc=(value)
    @b = (value >> 8) & 0xFF
    @c = value & 0xFF
  end

  def de
    (@d << 8) | @e
  end

  def de=(value)
    @d = (value >> 8) & 0xFF
    @e = value & 0xFF
  end

  def hl
    (@h << 8) | @l
  end

  def hl=(value)
    @h = (value >> 8) & 0xFF
    @l = value & 0xFF
  end

  def sp=(value)
    @sp = value & 0xFFFF
  end

  def read_two_bytes(address)
    low, high = read(address), read(address + 1)
    (high << 8) | low
  end

  def read_next_address
    read_two_bytes(@pc + 1)
  end

  def read(addr)
    case addr
    when ROM_RANGE
      @rom[addr]
    when VRAM_RANGE
      @vram[addr - VRAM_RANGE.begin]
    when WRAM_RANGE
      @wram[addr - WRAM_RANGE.begin]
    when ADDR_INP1
      read_inputs
    when IO_RANGE
      @io[addr - IO_RANGE.begin]
    when HRAM_RANGE
      @hram[addr - HRAM_RANGE.begin]
    else
      0xFF # adresses non mappées
    end
  end

  def read_inputs
    return 0xFF if key_state.nil? # Pas d'entrée, tous les bits sont à 1

    result = 0xFF
    if @inputs_selector == :direction
      result &= ~0x01 if key_state.up
      result &= ~0x02 if key_state.down
      result &= ~0x04 if key_state.left
      result &= ~0x08 if key_state.right
    elsif @inputs_selector == :button
      result &= ~0x01 if key_state.a
      result &= ~0x02 if key_state.b
      result &= ~0x04 if key_state.select
      result &= ~0x08 if key_state.start
    end
    result
  end

  def read_vram(addr, length = 1)
    if VRAM_RANGE.include?(addr)
      if length == 1
        @vram[addr - VRAM_RANGE.begin]
      else
        @vram[addr - VRAM_RANGE.begin, length]
      end
    else
      raise "Address #{addr.to_s(16)} is not in VRAM range"
    end
  end

  def write(addr, value)
    case addr
    when VRAM_RANGE
      @vram[addr - VRAM_RANGE.begin] = value
    when WRAM_RANGE
      @wram[addr - WRAM_RANGE.begin] = value
    when ADDR_INP1
      if value & 0x10 == 0
        @inputs_selector = :direction
      elsif value & 0x20 == 0
        @inputs_selector = :button
      else
        @inputs_selector = nil
      end
    when IO_RANGE
      @io[addr - IO_RANGE.begin] = value
    when HRAM_RANGE
      @hram[addr - HRAM_RANGE.begin] = value
    else
      # ROM et adresses non mappées sont en lecture seule
    end
  end

  def read_register_8(index)
    register_name = REGS_8[index]
    instance_variable_get("@#{register_name}")
  end

  def write_register_8(index, value)
    register_name = REGS_8[index]
    puts "Writing value #{value.to_s(16)} to register #{register_name.upcase}"
    instance_variable_set("@#{register_name}", value & 0xFF)
  end

  def read_register_16(index)
    register_name = REGS_16[index]
    send(register_name)
  end

  def write_register_16(index, value)
    register_name = REGS_16[index]
    send("#{register_name}=", value & 0xFFFF)
  end

  def call_opcode(return_address)
    # Pop next address, for future RET
    @sp = (@sp - 2) & 0xFFFF
    write(@sp, (return_address>> 8) & 0xFF)
    write(@sp + 1, return_address & 0xFF)
    # Jump
    @pc = read_next_address
  end

  def ret_opcode
    popped = (read(@sp) << 8) | read(@sp + 1)
    @pc = popped
    @sp = (@sp + 2) & 0xFFFF
  end

  def step
    nb_cycles = 0
    opcode = @rom[@pc]
    puts "Executing opcode #{opcode_name(opcode)} at #{@pc.to_s(16)}" unless @infinite_loop

    case opcode
    when 0x00 # NOP
      @pc += 1
      nb_cycles = 4

    when 0xc3 # JP a16
      @pc = read_two_bytes(@pc + 1)
      nb_cycles = 16
    when 0xc2 # JP NZ,a16
      @pc = flag_z ? (@pc + 3) : read_two_bytes(@pc + 1)
      nb_cycles = flag_z ? 12 : 16
    when 0xca # JP Z,a16
      @pc = flag_z ? read_two_bytes(@pc + 1) : (@pc + 3)
      nb_cycles = flag_z ? 16 : 12
    when 0xd2 # JP NC,a16
      @pc = flag_c ? (@pc + 3) : read_two_bytes(@pc + 1)
      nb_cycles = flag_c ? 12 : 16
    when 0xda # JP C,a16
      @pc = flag_c ? read_two_bytes(@pc + 1) : (@pc + 3)
      nb_cycles = flag_c ? 16 : 12

    when 0xcd # CALL a16
      call_opcode(@pc + 3)
      nb_cycles = 24

    when 0xc4 # CALL NZ,a16
      if flag_z
        @pc += 3
        nb_cycles = 12
      else
        call_opcode(@pc + 3)
        nb_cycles = 24
      end
    when 0xcc # CALL Z,a16
      if flag_z
        call_opcode(@pc + 3)
        nb_cycles = 24
      else
        @pc += 3
        nb_cycles = 12
      end
    when 0xd4 # CALL NC,a16
      if flag_c
        @pc += 3
        nb_cycles = 12
      else
        call_opcode(@pc + 3)
        nb_cycles = 24
      end
    when 0xdc # CALL C,a16
      if flag_c
        call_opcode(@pc + 3)
        nb_cycles = 24
      else
        @pc += 3
        nb_cycles = 12
      end

    when 0xC9 # RET
      ret_opcode
      nb_cycles = 16
    when 0xC0 # RET NZ
      if flag_z
        @pc += 1
        nb_cycles = 8
      else
        ret_opcode
        nb_cycles = 20
      end
    when 0xC8 # RET Z
      if flag_z
        ret_opcode
        nb_cycles = 20
      else
        @pc += 1
        nb_cycles = 8
      end
    when 0xD0 # RET NC
      if flag_c
        @pc += 1
        nb_cycles = 8
      else
        ret_opcode
        nb_cycles = 20
      end
    when 0xD8 # RET C
      if flag_c
        ret_opcode
        nb_cycles = 20
      else
        @pc += 1
        nb_cycles = 8
      end

    when 0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x3E # LD r8,d8
      reg_index = (opcode - 0x06) / 8
      write_register_8(reg_index, read(@pc + 1))
      @pc += 2
      nb_cycles = 8

    when 0x76 # HALT (MUST be before "LD (HL),r8" instructions in the 0x40..0x7F range)
      @running = false
      @pc += 1
      nb_cycles = 4

    when 0x40..0x7F # LD r8,r8
      dest_index = (opcode - 0x40) / 8
      src_index = (opcode - 0x40) % 8

      if src_index == 6 # LD r8,(HL)
        value = read(hl)
      else
        value = read_register_8(src_index)
      end

      if dest_index == 6 # LD (HL),r8
        write(hl, value)
      else
        write_register_8(dest_index, value)
      end

      @pc += 1
      nb_cycles = (src_index == 6 || dest_index == 6) ? 8 : 4

    when 0x01, 0x11, 0x21, 0x31 # LD rr,d16
      reg_index = (opcode - 0x01) / 0x10
      regs16 = {0 => :bc, 1 => :de, 2 => :hl, 3 => :sp}
      send("#{regs16[reg_index]}=", read_next_address)
      @pc += 3
      nb_cycles = 12

    when 0x02 # LD (BC),A
      write(bc, @a)
      @pc += 1
      nb_cycles = 8
    when 0x12 # LD (DE),A
      write(de, @a)
      @pc += 1
      nb_cycles = 8
    when 0x22 # LDI (HL),A
      write(hl, @a)
      self.hl = (hl + 1) & 0xFFFF
      @pc += 1
      nb_cycles = 8
    when 0x32 # LDD (HL),A
      write(hl, @a)
      self.hl = (hl - 1) & 0xFFFF
      @pc += 1
      nb_cycles = 8
    when 0x0A # LD A,(BC)
      self.a = read(bc)
      @pc += 1
      nb_cycles = 8
    when 0x1A # LD A,(DE)
      self.a = read(de)
      @pc += 1
      nb_cycles = 8
    when 0x2A # LDI A,(HL)
      self.a = read(hl)
      self.hl = (hl + 1) & 0xFFFF
      @pc += 1
      nb_cycles = 8
    when 0x3A # LDD A,(HL)
      self.a = read(hl)
      self.hl = (hl - 1) & 0xFFFF
      @pc += 1
      nb_cycles = 8

    when 0xEA # LD (a16),A
      address = read_next_address
      write(address, @a)
      @pc += 3
      nb_cycles = 16

    when 0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x3D # DEC r8
      reg_index = (opcode - 0x05) / 8
      new_value = (read_register_8(reg_index) - 1) & 0xFF
      write_register_8(reg_index, new_value)
      self.flag_z = (new_value == 0)
      @pc += 1
      nb_cycles = 4

    when 0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x3C # INC r8
      reg_index = (opcode - 0x04) / 8
      new_value = (read_register_8(reg_index) + 1) & 0xFF
      write_register_8(reg_index, new_value)
      self.flag_z = (new_value == 0)
      @pc += 1
      nb_cycles = 4

    when 0x03, 0x13, 0x23, 0x33 # INC rr
      reg_index = (opcode - 0x03) / 0x10
      value = (read_register_16(reg_index) + 1) & 0xFFFF
      write_register_16(reg_index, value)
      @pc += 1
      nb_cycles = 8

    when 0x34, 0x35 # INC (HL), DEC (HL)
      sign = opcode == 0x34 ? 1 : -1
      original = read(hl)
      value = (original + sign) & 0xFF
      write(hl, value)

      self.flag_z = (value == 0)
      self.flag_h = sign == 1 ? (original & 0xF) == 0xF : (original & 0xF) == 0x0
      self.flag_n = sign == -1
      @pc += 1
      nb_cycles = 12

    when 0xb, 0x1b, 0x2b, 0x3b # DEC rr
      reg_index = (opcode - 0x0b) / 0x10
      value = (read_register_16(reg_index) - 1) & 0xFFFF
      write_register_16(reg_index, value)
      @pc += 1
      nb_cycles = 8

    when 0x80..0x87 # ADD A,r8
      reg_index = opcode - 0x80
      value = opcode == 0x86 ? read(hl) : read_register_8(reg_index)
      result = @a + value
      self.flag_z = (result & 0xFF) == 0
      self.flag_n = false
      self.flag_h = ((@a & 0xF) + (value & 0xF)) > 0xF
      self.flag_c = result > 0xFF
      @a = result & 0xFF
      @pc += 1
      nb_cycles = (opcode == 0x86) ? 8 : 4

    when 0x90..0x97 # SUB A,r8
      reg_index = opcode - 0x90
      value = opcode == 0x96 ? read(hl) : read_register_8(reg_index)
      result = @a - value
      self.flag_z = (result & 0xFF) == 0
      self.flag_n = true
      self.flag_h = (@a & 0xF) < (value & 0xF)
      self.flag_c = @a < value
      @a = result & 0xFF
      @pc += 1
      nb_cycles = (opcode == 0x96) ? 8 : 4

    when 0xA0..0xA7 # AND A,r8
      reg_index = opcode - 0xA0
      value = opcode == 0xA6 ? read(hl) : read_register_8(reg_index)
      @a &= value
      self.flag_z = (@a == 0)
      self.flag_n = false
      self.flag_h = true
      self.flag_c = false
      @pc += 1
      nb_cycles = (opcode == 0xA6) ? 8 : 4

    when 0xB0..0xB7 # OR A,r8
      reg_index = opcode - 0xB0
      value = opcode == 0xB6 ? read(hl) : read_register_8(reg_index)
      @a |= value
      self.flag_z = (@a == 0)
      self.flag_n = false
      self.flag_h = false
      self.flag_c = false
      @pc += 1
      nb_cycles = (opcode == 0xB6) ? 8 : 4

    when 0xA8..0xAF # XOR A,r8
      reg_index = opcode - 0xA8
      value = opcode == 0xAE ? read(hl) : read_register_8(reg_index)
      @a ^= value
      self.flag_z = (@a == 0)
      self.flag_n = false
      self.flag_h = false
      self.flag_c = false
      @pc += 1
      nb_cycles = (opcode == 0xAE) ? 8 : 4

    when 0xB8..0xBF # CP A,r8
      reg_index = opcode - 0xB8
      value = opcode == 0xBE ? read(hl) : read_register_8(reg_index)
      result = @a - value
      self.flag_z = (result & 0xFF) == 0
      self.flag_n = true
      self.flag_h = (@a & 0xF) < (value & 0xF)
      self.flag_c = @a < value
      @pc += 1
      nb_cycles = (opcode == 0xBE) ? 8 : 4

    when 0xC5, 0xD5, 0xE5 # PUSH BC, DE, HL
      reg_index = (opcode - 0xC5) / 0x10
      value = read_register_16(reg_index)
      @sp = (@sp - 2) & 0xFFFF
      write(@sp, (value >> 8) & 0xFF)
      write(@sp + 1, value & 0xFF)
      @pc += 1
      nb_cycles = 16

    when 0xF5 # PUSH AF
      value = (@a << 8) | @f
      @sp = (@sp - 2) & 0xFFFF
      write(@sp, (value >> 8) & 0xFF)
      write(@sp + 1, value & 0xFF)
      @pc += 1
      nb_cycles = 16

    when 0xC1, 0xD1, 0xE1 # POP BC, DE, HL
      reg_index = (opcode - 0xC1) / 0x10
      value = (read(@sp) << 8) | read(@sp + 1)
      write_register_16(reg_index, value)
      @sp = (@sp + 2) & 0xFFFF
      @pc += 1
      nb_cycles = 12

    when 0xF1 # POP AF
      @a = read(@sp)
      @f = read(@sp + 1)
      @sp = (@sp + 2) & 0xFFFF
      @pc += 1
      nb_cycles = 12

    when 0x20 # JR NZ,r8
      offset = read(@pc + 1)
      mem = flag_z ? 0 : (offset < 128 ? offset : offset - 256)
      @pc += 2 + mem
      nb_cycles = flag_z ? 8 : 12

    when 0x28 # JR Z,r8
      offset = read(@pc + 1)
      mem = flag_z ? (offset < 128 ? offset : offset - 256) : 0
      @pc += 2 + mem
      nb_cycles = flag_z ? 12 : 8

    when 0x30 # JR NC,r8
      offset = read(@pc + 1)
      mem = flag_c ? 0 : (offset < 128 ? offset : offset - 256)
      @pc += 2 + mem
      nb_cycles = flag_c ? 8 : 12

    when 0x38 # JR C,r8
      offset = read(@pc + 1)
      mem = flag_c ? (offset < 128 ? offset : offset - 256) : 0
      @pc += 2 + mem
      nb_cycles = flag_c ? 12 : 8

    when 0x18 # JR r8
      offset = read(@pc + 1)
      if offset == 0xFE
        @infinite_loop = true
      else
        @pc += 2 + (offset < 128 ? offset : offset - 256)
      end
      nb_cycles = 12

    when 0xCB # PREFIX CB (opcodes étendus)
      cb_opcode = read(@pc + 1)
      nb_cycles = process_cb_opcode(cb_opcode)
      @pc += 2

    else
      handle_unknown_opcode(opcode)
    end

    display_state
    nb_cycles
  end

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
        flag_c ? (to_the_left ? 0x01 : 0x80) : 0
      when :arithmetic
        to_the_left ? 0 : (old_value & 0x80)
      when :logical
        0
      end

    new_flag_c = bit_to_rotate == 1
    write_cb_value_and_flags(target, new_value & 0xFF, new_flag_c)
  end

  def process_swap(target)
    old_value = read_cb_value(target)
    new_value = ((old_value & 0x0F) << 4) | ((old_value & 0xF0) >> 4)

    write_cb_value_and_flags(target, new_value)
  end

  def process_cb_bit_test(cb_opcode, target)
    bit_index = (cb_opcode - 0x40) / 8
    value = read_cb_value(target)
    self.flag_z = (value & (1 << bit_index)) == 0
    self.flag_n = false
    self.flag_h = true
    # C flag is unaffected

    cb_value_is_hl?(target) ? 12 : 8
  end

  def process_cb_bit_reset(cb_opcode, target)
    bit_index = (cb_opcode - 0x80) / 8
    value = read_cb_value(target)
    new_value = value & ~(1 << bit_index)
    write_cb_value_and_flags(target, new_value, flag_c) # C flag is unaffected
  end

  def process_cb_bit_set(cb_opcode, target)
    bit_index = (cb_opcode - 0xC0) / 8
    value = read_cb_value(target)
    new_value = value | (1 << bit_index)
    write_cb_value_and_flags(target, new_value, flag_c) # C flag is unaffected
  end

  def read_cb_value(target)
    cb_value_is_hl?(target) ? read(hl) : read_register_8(target)
  end

  def write_cb_value_and_flags(target, value, new_flag_c = false)
    if cb_value_is_hl?(target)
      write(hl, value)
    else
      write_register_8(target, value)
    end

    self.flag_z = value == 0
    self.flag_n = false
    self.flag_h = false
    self.flag_c = new_flag_c

    cb_value_is_hl?(target) ? 16 : 8
  end

  def cb_value_is_hl?(value)
    value == 6
  end

  def handle_unknown_opcode(opcode)
    puts "Unknown opcode #{opcode.to_s(16)} at #{@pc.to_s(16)}"
    @running = false
  end

  def display_state
    return if @infinite_loop

    puts "  PC: 0x#{@pc.to_s(16)}, A: #{@a.to_s(16)}, BC: #{bc.to_s(16)}, DE: #{de.to_s(16)}, HL: #{hl.to_s(16)}"
  end

  def opcode_name(opcode)
    case opcode
    when 0x00 then "NOP"
    when 0xc3 then "JP a16"
    when 0x3E then "LD A,d8"
    when 0x06 then "LD B,d8"
    when 0x01 then "LD BC,d16"
    when 0x21 then "LD HL,d16"
    when 0x11 then "LD DE,d16"
    when 0x7e then "LD A,(HL)"
    when 0x12 then "LD (DE),A"
    when 0xEA then "LD (a16),A"
    when 0x23 then "INC HL"
    when 0x13 then "INC DE"
    when 0xb then "DEC BC"
    when 0x05 then "DEC B"
    when 0x20 then "JR NZ,r8"
    when 0x18 then "JR r8"
    else "UNKNOWN (#{opcode.to_s(16)})"
    end
  end

  def running?
    @running
  end
end
