# GameBoy DMG-01 CPU Emulator en Ruby
class CPU
  REGS_8 = [:b, :c, :d, :e, :h, :l, nil, :a]
  REGS_16 = [:bc, :de, :hl, :sp]
  FLAGS = %i[z n h c]

  attr_reader :mmu, :pc, :sp, :infinite_loop

  def initialize(mmu)
    @mmu = mmu

    @infinite_loop = false
    @running = true

    # Utilisé pour stocker des opérations différées
    # ex: EI prend effet après l'instruction suivante
    @pending_operations = []

    # Registres spéciaux
    @pc = 0x100  # point d'entrée standard des ROMs GB
    @sp = 0xFFFE # pile initiale

    # Registres généraux
    @registers = {
      a: 0,
      f: 0,
      b: 0,
      c: 0,
      d: 0,
      e: 0,
      h: 0,
      l: 0
    }

    initialize_register_accessors
    initialize_flags_accessors
  end

  def initialize_register_accessors
    %i[a b c d e h l f].each do |reg|
      define_singleton_method(reg) { read_register(reg) }
      define_singleton_method(:"#{reg}=") { |v| write_register(reg, v) }
    end
  end

  def initialize_flags_accessors
    %i[z n h c].each do |flag|
      define_singleton_method("flag_#{flag}") { read_flag(flag) }
      define_singleton_method("flag_#{flag}=") { |v| write_flag(flag, v) }
    end
  end

  def read_register(name)
    @registers[name]
  end

  def write_register(name, value)
    @registers[name] = value & 0xFF
  end

  def flag_bit(flag)
    0x80 >> FLAGS.index(flag)
  end

  def read_flag(flag)
    (f & flag_bit(flag)) != 0
  end

  def write_flag(flag, value)
    self.f = value ? f | flag_bit(flag) : f & ~flag_bit(flag)
  end

  def af
    (a << 8) | f
  end

  def af=(value)
    self.a = (value >> 8) & 0xFF
    self.f = value & 0xF0 # les 4 bits de poids faible de F sont toujours 0
  end

  def bc
    (b << 8) | c
  end

  def bc=(value)
    self.b = (value >> 8) & 0xFF
    self.c = value & 0xFF
  end

  def de
    (d << 8) | e
  end

  def de=(value)
    self.d = (value >> 8) & 0xFF
    self.e = value & 0xFF
  end

  def hl
    (h << 8) | l
  end

  def hl=(value)
    self.h = (value >> 8) & 0xFF
    self.l = value & 0xFF
  end

  def sp=(value)
    @sp = value & 0xFFFF
  end

  def read(addr)
    mmu.read(addr)
  end
  
  def read_next_address
    mmu.read_16(@pc + 1)
  end

  def write(addr, value)
    mmu.write(addr, value)
  end

  def read_register_8(index)
    @registers[REGS_8[index]]
  end

  def write_register_8(index, value)
    @registers[REGS_8[index]] = value & 0xFF
  end

  def read_register_16(index)
    register_name = REGS_16[index]
    send(register_name)
  end

  def write_register_16(index, value)
    register_name = REGS_16[index]
    send("#{register_name}=", value & 0xFFFF)
  end

  def call_opcode(return_address, target_address = nil)
    # Pop next address, for future RET
    @sp = (@sp - 2) & 0xFFFF
    write(@sp, (return_address>> 8) & 0xFF)
    write(@sp + 1, return_address & 0xFF)
    # Jump
    @pc = target_address || read_next_address
  end

  def ret_opcode
    popped = (read(@sp) << 8) | read(@sp + 1)
    @pc = popped
    @sp = (@sp + 2) & 0xFFFF
  end

  def step
    execute_pending_operations

    opcode = mmu.rom[@pc]
    puts "Executing opcode #{opcode_name(opcode)} at #{@pc.to_s(16)}" unless infinite_loop

    process_opcode(opcode).tap do |nb_cycles|
      process_timers(nb_cycles)
      process_interrupts
    end
  end

  def execute_pending_operations
    @pending_operations.each(&:call)
    @pending_operations.clear
  end

  def process_opcode(opcode)
    nb_cycles = 0

    case opcode
    when 0x00 # NOP
      @pc += 1
      nb_cycles = 4

    when 0xc3 # JP a16
      @pc = read_next_address
      nb_cycles = 16
    when 0xc2 # JP NZ,a16
      @pc = flag_z ? (@pc + 3) : read_next_address
      nb_cycles = flag_z ? 12 : 16
    when 0xca # JP Z,a16
      @pc = flag_z ? read_next_address : (@pc + 3)
      nb_cycles = flag_z ? 16 : 12
    when 0xd2 # JP NC,a16
      @pc = flag_c ? (@pc + 3) : read_next_address
      nb_cycles = flag_c ? 12 : 16
    when 0xda # JP C,a16
      @pc = flag_c ? read_next_address : (@pc + 3)
      nb_cycles = flag_c ? 16 : 12

    when 0xf3 # DI
      mmu.interrupts_enabled = false
      @pc += 1
      nb_cycles = 4

    when 0xfb # EI
      # EI ne prend effet qu'après l'instruction suivante
      @pending_operations << -> { mmu.interrupts_enabled = true }
      @pc += 1
      nb_cycles = 4

    when 0xd9 # RETI
      ret_opcode
      mmu.interrupts_enabled = true
      nb_cycles = 16

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
      write_register_16(reg_index, read_next_address)
      @pc += 3
      nb_cycles = 12

    when 0x02 # LD (BC),A
      write(bc, a)
      @pc += 1
      nb_cycles = 8
    when 0x12 # LD (DE),A
      write(de, a)
      @pc += 1
      nb_cycles = 8
    when 0x22 # LDI (HL),A
      write(hl, a)
      self.hl = (hl + 1) & 0xFFFF
      @pc += 1
      nb_cycles = 8
    when 0x32 # LDD (HL),A
      write(hl, a)
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
      write(address, a)
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
      result = a + value
      self.flag_z = (result & 0xFF) == 0
      self.flag_n = false
      self.flag_h = ((a & 0xF) + (value & 0xF)) > 0xF
      self.flag_c = result > 0xFF
      self.a = result & 0xFF
      @pc += 1
      nb_cycles = (opcode == 0x86) ? 8 : 4

    when 0x90..0x97 # SUB A,r8
      reg_index = opcode - 0x90
      value = opcode == 0x96 ? read(hl) : read_register_8(reg_index)
      result = a - value
      self.flag_z = (result & 0xFF) == 0
      self.flag_n = true
      self.flag_h = (a & 0xF) < (value & 0xF)
      self.flag_c = a < value
      self.a = result & 0xFF
      @pc += 1
      nb_cycles = (opcode == 0x96) ? 8 : 4

    when 0xA0..0xA7 # AND A,r8
      reg_index = opcode - 0xA0
      value = opcode == 0xA6 ? read(hl) : read_register_8(reg_index)
      self.a = a & value
      self.flag_z = (a == 0)
      self.flag_n = false
      self.flag_h = true
      self.flag_c = false
      @pc += 1
      nb_cycles = (opcode == 0xA6) ? 8 : 4

    when 0xB0..0xB7 # OR A,r8
      reg_index = opcode - 0xB0
      value = opcode == 0xB6 ? read(hl) : read_register_8(reg_index)
      self.a = a | value
      self.flag_z = (a == 0)
      self.flag_n = false
      self.flag_h = false
      self.flag_c = false
      @pc += 1
      nb_cycles = (opcode == 0xB6) ? 8 : 4

    when 0xA8..0xAF # XOR A,r8
      reg_index = opcode - 0xA8
      value = opcode == 0xAE ? read(hl) : read_register_8(reg_index)
      self.a = a ^ value
      self.flag_z = (a == 0)
      self.flag_n = false
      self.flag_h = false
      self.flag_c = false
      @pc += 1
      nb_cycles = (opcode == 0xAE) ? 8 : 4

    when 0xB8..0xBF # CP A,r8
      reg_index = opcode - 0xB8
      value = opcode == 0xBE ? read(hl) : read_register_8(reg_index)
      result = a - value
      self.flag_z = (result & 0xFF) == 0
      self.flag_n = true
      self.flag_h = (a & 0xF) < (value & 0xF)
      self.flag_c = a < value
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
      value = (a << 8) | f
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
      self.a = read(@sp)
      self.f = read(@sp + 1) & 0xF0
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

  def process_timers(nb_cycles)
    mmu.increment_timers(nb_cycles)
  end

  def process_interrupts
    return unless mmu.interrupts_enabled
    return if (mmu.interrupts_requested_mask.values & mmu.interrupts_enabled_mask.values).none?

    # trouve la requete d'interruption la plus prioritaire
    interrupt = mmu.most_important_interrupt
    return if interrupt.nil?

    # passe IME à 0 et efface la requete d'interruption (évite inter. imbriquées)
    mmu.interrupts_enabled = false
    mmu.clear_interrupt_requested(interrupt)

    # appelle le handler
    call_opcode(@pc, mmu.interrupt_vector(interrupt))
    # RETI reprend l'exécution (pop PC de la stack et set IME à 1)
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
    return if infinite_loop

    puts "  PC: 0x#{@pc.to_s(16)}, A: #{a.to_s(16)}, BC: #{bc.to_s(16)}, DE: #{de.to_s(16)}, HL: #{hl.to_s(16)}"
  end

  def opcode_name(opcode)
    r8  = ->(i) { %w[B C D E H L (HL) A][i] }
    r16 = ->(i) { %w[BC DE HL SP][i] }

    case opcode
    when 0x00 then "NOP"
    when 0x76 then "HALT"

    # LD r8,d8
    when 0x06 then "LD B,d8"
    when 0x0E then "LD C,d8"
    when 0x16 then "LD D,d8"
    when 0x1E then "LD E,d8"
    when 0x26 then "LD H,d8"
    when 0x2E then "LD L,d8"
    when 0x3E then "LD A,d8"

    # LD rr,d16
    when 0x01 then "LD BC,d16"
    when 0x11 then "LD DE,d16"
    when 0x21 then "LD HL,d16"
    when 0x31 then "LD SP,d16"

    # LD r8,r8
    when 0x40..0x7F
      dst = r8.call((opcode - 0x40) / 8)
      src = r8.call((opcode - 0x40) % 8)
      "LD #{dst},#{src}"

    # LD (rr),A / LD A,(rr)
    when 0x02 then "LD (BC),A"
    when 0x12 then "LD (DE),A"
    when 0x22 then "LDI (HL),A"
    when 0x32 then "LDD (HL),A"
    when 0x0A then "LD A,(BC)"
    when 0x1A then "LD A,(DE)"
    when 0x2A then "LDI A,(HL)"
    when 0x3A then "LDD A,(HL)"
    when 0xEA then "LD (a16),A"

    # INC r8
    when 0x04 then "INC B"
    when 0x0C then "INC C"
    when 0x14 then "INC D"
    when 0x1C then "INC E"
    when 0x24 then "INC H"
    when 0x2C then "INC L"
    when 0x34 then "INC (HL)"
    when 0x3C then "INC A"

    # DEC r8
    when 0x05 then "DEC B"
    when 0x0D then "DEC C"
    when 0x15 then "DEC D"
    when 0x1D then "DEC E"
    when 0x25 then "DEC H"
    when 0x2D then "DEC L"
    when 0x35 then "DEC (HL)"
    when 0x3D then "DEC A"

    # INC/DEC rr
    when 0x03 then "INC BC"
    when 0x13 then "INC DE"
    when 0x23 then "INC HL"
    when 0x33 then "INC SP"
    when 0x0B then "DEC BC"
    when 0x1B then "DEC DE"
    when 0x2B then "DEC HL"
    when 0x3B then "DEC SP"

    # ALU A,r8
    when 0x80..0x87 then "ADD A,#{r8.call(opcode - 0x80)}"
    when 0x90..0x97 then "SUB A,#{r8.call(opcode - 0x90)}"
    when 0xA0..0xA7 then "AND A,#{r8.call(opcode - 0xA0)}"
    when 0xA8..0xAF then "XOR A,#{r8.call(opcode - 0xA8)}"
    when 0xB0..0xB7 then "OR A,#{r8.call(opcode - 0xB0)}"
    when 0xB8..0xBF then "CP A,#{r8.call(opcode - 0xB8)}"

    # PUSH/POP
    when 0xC5 then "PUSH BC"
    when 0xD5 then "PUSH DE"
    when 0xE5 then "PUSH HL"
    when 0xF5 then "PUSH AF"
    when 0xC1 then "POP BC"
    when 0xD1 then "POP DE"
    when 0xE1 then "POP HL"
    when 0xF1 then "POP AF"

    # JP
    when 0xC3 then "JP a16"
    when 0xC2 then "JP NZ,a16"
    when 0xCA then "JP Z,a16"
    when 0xD2 then "JP NC,a16"
    when 0xDA then "JP C,a16"

    # JR
    when 0x18 then "JR r8"
    when 0x20 then "JR NZ,r8"
    when 0x28 then "JR Z,r8"
    when 0x30 then "JR NC,r8"
    when 0x38 then "JR C,r8"

    # CALL
    when 0xCD then "CALL a16"
    when 0xC4 then "CALL NZ,a16"
    when 0xCC then "CALL Z,a16"
    when 0xD4 then "CALL NC,a16"
    when 0xDC then "CALL C,a16"

    # RET
    when 0xC9 then "RET"
    when 0xC0 then "RET NZ"
    when 0xC8 then "RET Z"
    when 0xD0 then "RET NC"
    when 0xD8 then "RET C"

    # PREFIX CB
    when 0xCB then "PREFIX CB"

    else "UNKNOWN (0x#{opcode.to_s(16).upcase})"
    end
  end

  def running?
    @running
  end
end
