# GameBoy DMG-01 CPU Emulator en Ruby
class CPU
  # Accéder aux registres généraux et spéciaux
  module RegisterAccessors
    REGS_8 = [:b, :c, :d, :e, :h, :l, nil, :a]
    REGS_16 = [:bc, :de, :hl, :sp]
    FLAGS = %i[z n h c]

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

    # Registers (16 bits)
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

    # Registers (8 bits)
    def a
      @registers[:a]
    end

    def a=(value)
      @registers[:a] = value & 0xFF
    end

    def b
      @registers[:b]
    end

    def b=(value)
      @registers[:b] = value & 0xFF
    end

    def c
      @registers[:c]
    end

    def c=(value)
      @registers[:c] = value & 0xFF
    end

    def d
      @registers[:d]
    end

    def d=(value)
      @registers[:d] = value & 0xFF
    end

    def e
      @registers[:e]
    end

    def e=(value)
      @registers[:e] = value & 0xFF
    end

    def h
      @registers[:h]
    end

    def h=(value)
      @registers[:h] = value & 0xFF
    end

    def l
      @registers[:l]
    end

    def l=(value)
      @registers[:l] = value & 0xFF
    end

    def f
      @registers[:f]
    end

    def f=(value)
      @registers[:f] = value & 0xF0
    end

    # Flags
    def read_flag(flag)
      (f & flag_bit(flag)) != 0
    end

    def write_flag(flag, value)
      self.f = value ? f | flag_bit(flag) : f & ~flag_bit(flag)
    end

    def flag_z
      read_flag(:z)
    end

    def flag_z=(value)
      write_flag(:z, value)
    end

    def flag_n
      read_flag(:n)
    end

    def flag_n=(value)
      write_flag(:n, value)
    end

    def flag_h
      read_flag(:h)
    end

    def flag_h=(value)
      write_flag(:h, value)
    end

    def flag_c
      read_flag(:c)
    end

    def flag_c=(value)
      write_flag(:c, value)
    end

    def flag_bit(flag)
      0x80 >> FLAGS.index(flag)
    end
  end
end
