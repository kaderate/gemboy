# GameBoy DMG-01 CPU Emulator en Ruby
class CPU
  attr_accessor :a, :f

  def initialize(rom_bytes)
    @rom = rom_bytes

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
    puts "Setting HL to #{value.to_s(16)}"
    @h = (value >> 8) & 0xFF
    @l = value & 0xFF
  end

  def step
    opcode = @rom[@pc]
    puts "Executing opcode #{opcode.to_s(16)} at #{@pc.to_s(16)}" unless @infinite_loop

    case opcode
    when 0x00 # NOP
      @pc += 1

    when 0xc3 # JP a16
      low = @rom[@pc + 1]
      high = @rom[@pc + 2]
      @pc = (high << 8) | low

    when 0x3E # LD A,d8
      @a = @rom[@pc + 1]
      @pc += 2

    when 0x01 # LD BC,d16
      low = @rom[@pc + 1]
      high = @rom[@pc + 2]
      bc = (high << 8) | low
      @pc += 3

    when 0x21 # LD HL,d16
      low = @rom[@pc + 1]
      high = @rom[@pc + 2]
      binding.irb
      hl = (high << 8) | low
      @pc += 3

    when 0x11 # LD DE,d16
      low = @rom[@pc + 1]
      high = @rom[@pc + 2]
      de = (high << 8) | low
      @pc += 3

    when 0x7e # LD A,(HL)
      binding.irb
      @a = @rom[hl]
      @pc += 1

    when 0x12 # LD (DE),A
      @rom[de] = @a
      @pc += 1

    when 0x23 # INC HL
      hl = (hl + 1) & 0xFFFF
      @pc += 1

    when 0x13 # INC DE
      de = (de + 1) & 0xFFFF
      @pc += 1

    when 0xb # DEC BC
      bc = (bc - 1) & 0xFFFF
      @pc += 1

    when 0x20 # JR NZ,r8
      offset = @rom[@pc + 1]
      if @a != 0
        @pc += 2 + (offset < 128 ? offset : offset - 256)
      else
        @pc += 2
      end

    when 0x18 # JR r8
      offset = @rom[@pc + 1]
      @infinite_loop = true if offset == 0xFE # JR -2, utilisé pour les boucles infinies
    else
      puts "Unknown opcode #{opcode.to_s(16)} at #{@pc.to_s(16)}"
      @running = false
    end

    display_state
  end

  def display_state
    return if @infinite_loop

    puts "PC: 0x#{@pc.to_s(16)}, A: #{@a.to_s(16)}, BC: #{bc.to_s(16)}, DE: #{de.to_s(16)}, HL: #{hl.to_s(16)}"
    puts ''
  end

  def running?
    @running
  end
end
