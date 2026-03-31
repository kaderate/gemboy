# GameBoy DMG-01 CPU Emulator en Ruby
class CPU
  ADDR_LCDC = 0xFF40

  attr_accessor :a, :f

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
    x = @io[ADDR_LCDC - 0xFF00]
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
    when 0x0000..0x7FFF
      @rom[addr]
    when 0x8000..0x9FFF # VRAM
      @vram[addr - 0x8000]
    when 0xC000..0xDFFF # WRAM
      @wram[addr - 0xC000]
    when 0xFF00..0xFF7F # I/O
      @io[addr - 0xFF00]
    else
      0xFF # adresses non mappées
    end
  end

  def read_vram(addr, length = 1)
    @vram[addr - 0x8000, length]
  end

  def write(addr, value)
    case addr
    when 0x8000..0x9FFF
      @vram[addr - 0x8000] = value
    when 0xC000..0xDFFF
      @wram[addr - 0xC000] = value
    when 0xFF00..0xFF7F
      @io[addr - 0xFF00] = value
    else
      # ROM et adresses non mappées sont en lecture seule
    end
  end

  def step
    opcode = @rom[@pc]
    puts "Executing opcode #{opcode_name(opcode)} at #{@pc.to_s(16)}" unless @infinite_loop

    case opcode
    when 0x00 # NOP
      @pc += 1

    when 0xc3 # JP a16
      @pc = read_two_bytes(@pc + 1)

    when 0x01 # LD BC,d16
      self.bc = read_next_address
      @pc += 3

    when 0x06 # LD B,d8
      @b = read(@pc + 1)
      @pc += 2

    when 0x11 # LD DE,d16
      self.de = read_next_address
      @pc += 3

    when 0x12 # LD (DE),A
      write(de, @a)
      @pc += 1

    when 0xEA # LD (a16),A
      address = read_next_address
      write(address, @a)
      @pc += 3

    when 0x21 # LD HL,d16
      self.hl = read_next_address
      @pc += 3

    when 0x7e # LD A,(HL)
      @a = read(hl)
      @pc += 1

    when 0x3E # LD A,d8
      @a = read(@pc + 1)
      @pc += 2

    when 0x23 # INC HL
      self.hl = (hl + 1) & 0xFFFF
      @pc += 1

    when 0x13 # INC DE
      self.de = (de + 1) & 0xFFFF
      @pc += 1

    when 0x05 # DEC B
      @b = (@b - 1) & 0xFF
      self.flag_z = (@b == 0)
      @pc += 1

    when 0xb # DEC BC
      self.bc = (bc - 1) & 0xFFFF
      @pc += 1

    when 0x20 # JR NZ,r8
      offset = read(@pc + 1)
      if !flag_z
        @pc += 2 + (offset < 128 ? offset : offset - 256)
      else
        @pc += 2
      end

    when 0x18 # JR r8
      offset = read(@pc + 1)
      if offset == 0xFE
        @infinite_loop = true
      else
        @pc += 2 + (offset < 128 ? offset : offset - 256)
      end
    else
      puts "Unknown opcode #{opcode.to_s(16)} at #{@pc.to_s(16)}"
      @running = false
    end

    display_state
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
    when 0x01 then "LD BC,d16"
    when 0x21 then "LD HL,d16"
    when 0x11 then "LD DE,d16"
    when 0x7e then "LD A,(HL)"
    when 0x12 then "LD (DE),A"
    when 0x23 then "INC HL"
    when 0x13 then "INC DE"
    when 0xb then "DEC BC"
    when 0x20 then "JR NZ,r8"
    when 0x18 then "JR r8"
    else "UNKNOWN"
    end
  end

  def running?
    @running
  end
end
