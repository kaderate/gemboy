# GameBoy DMG-01 CPU Emulator en Ruby
class CPU
  ADDR_LCDC = 0xFF40
  ROM_RANGE = 0x0000..0x7FFF
  VRAM_RANGE = 0x8000..0x9FFF

  attr_accessor :a, :f
  attr_reader :pc, :sp, :b, :c, :d, :e, :h, :l

  def initialize(rom_bytes)
    @rom = rom_bytes
    @vram = Array.new(0x2000, 0) # 8KB de VRAM
    @wram = Array.new(0x2000, 0) # 8KB de WRAM
    @io = Array.new(0x80, 0)     # 128 octets d'I/O

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
    when 0xC000..0xDFFF # WRAM
      @wram[addr - 0xC000]
    when 0xFF00..0xFF7F # I/O
      @io[addr - 0xFF00]
    else
      0xFF # adresses non mappées
    end
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
    when 0xC000..0xDFFF
      @wram[addr - 0xC000] = value
    when 0xFF00..0xFF7F
      @io[addr - 0xFF00] = value
    else
      # ROM et adresses non mappées sont en lecture seule
    end
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

    when 0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x3E # LD r8,d8
      reg_index = (opcode - 0x06) / 8
      regs = {0 => :b, 1 => :c, 2 => :d, 3 => :e, 4 => :h, 5 => :l, 7 => :a}
      instance_variable_set("@#{regs[reg_index]}", read(@pc + 1))
      @pc += 2
      nb_cycles = 8

    when 0x76 # HALT (MUST be before "LD (HL),r8" instructions in the 0x40..0x7F range)
      @running = false
      @pc += 1
      nb_cycles = 4

    when 0x40..0x7F # LD r8,r8
      dest_index = (opcode - 0x40) / 8
      src_index = (opcode - 0x40) % 8
      regs = {0 => :b, 1 => :c, 2 => :d, 3 => :e, 4 => :h, 5 => :l, 7 => :a}

      if src_index == 6 # LD r8,(HL)
        value = read(hl)
      else
        value = instance_variable_get("@#{regs[src_index]}")
      end

      if dest_index == 6 # LD (HL),r8
        write(hl, value)
      else
        instance_variable_set("@#{regs[dest_index]}", value)
      end

      @pc += 1
      nb_cycles = (src_index == 6 || dest_index == 6) ? 8 : 4
    # when 0x7e # LD A,(HL)
    #   @a = read(hl)
    #   @pc += 1
    #   nb_cycles = 8

    when 0x01 # LD BC,d16
      self.bc = read_next_address
      @pc += 3
      nb_cycles = 12
    when 0x11 # LD DE,d16
      self.de = read_next_address
      @pc += 3
      nb_cycles = 12
    when 0x21 # LD HL,d16
      self.hl = read_next_address
      @pc += 3
      nb_cycles = 12

    when 0x12 # LD (DE),A
      write(de, @a)
      @pc += 1
      nb_cycles = 8

    when 0xEA # LD (a16),A
      address = read_next_address
      write(address, @a)
      @pc += 3
      nb_cycles = 16

    when 0x23 # INC HL
      self.hl = (hl + 1) & 0xFFFF
      @pc += 1
      nb_cycles = 8

    when 0x13 # INC DE
      self.de = (de + 1) & 0xFFFF
      @pc += 1
      nb_cycles = 8

    when 0x05 # DEC B
      @b = (@b - 1) & 0xFF
      self.flag_z = (@b == 0)
      @pc += 1
      nb_cycles = 4

    when 0xb # DEC BC
      self.bc = (bc - 1) & 0xFFFF
      @pc += 1
      nb_cycles = 8

    when 0x20 # JR NZ,r8
      offset = read(@pc + 1)
      if !flag_z
        @pc += 2 + (offset < 128 ? offset : offset - 256)
      else
        @pc += 2
      end
      nb_cycles = flag_z ? 8 : 12

    when 0x18 # JR r8
      offset = read(@pc + 1)
      if offset == 0xFE
        @infinite_loop = true
      else
        @pc += 2 + (offset < 128 ? offset : offset - 256)
      end
      nb_cycles = 12

    else
      puts "Unknown opcode #{opcode.to_s(16)} at #{@pc.to_s(16)}"
      @running = false
    end

    display_state
    nb_cycles
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
