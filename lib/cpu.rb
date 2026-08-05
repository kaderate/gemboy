require 'forwardable'
require 'logger'
require_relative 'micro_op'
require_relative 'cpu/register_accessors'

# GameBoy DMG-01 CPU Emulator en Ruby
class CPU # rubocop:disable Metrics/ClassLength
  extend Forwardable

  T_CYCLES_PER_SECOND = 4_194_304

  class UnknownOpcode < StandardError; end

  include CPU::RegisterAccessors

  attr_reader :pc, :mmu, :infinite_loop, :opcodes_with_micro_ops, :config
  attr_accessor :registers, :sp, :halted

  Config = Struct.new(:use_micro_ops)

  # Table de dispatch indexée par opcode (256 entrées), remplacement O(1) du
  # case/when séquentiel. Ordre des affectations = ordre du case original :
  # les ranges génériques d'abord, les overrides ponctuels ensuite.
  OPCODE_DISPATCH = Array.new(256, :op_unknown).tap do |t|
    t[0x00] = :op_nop
    [0x07, 0x0F, 0x17, 0x1F].each { |op| t[op] = :op_rotate_a }
    t[0xc3] = :op_jp_a16
    t[0xc2] = :op_jp_nz_a16
    t[0xca] = :op_jp_z_a16
    t[0xd2] = :op_jp_nc_a16
    t[0xda] = :op_jp_c_a16
    t[0xe9] = :op_jp_hl
    t[0xf3] = :op_di
    t[0xfb] = :op_ei
    t[0xd9] = :op_reti
    t[0xcd] = :op_call_a16
    t[0xc4] = :op_call_nz_a16
    t[0xcc] = :op_call_z_a16
    t[0xd4] = :op_call_nc_a16
    t[0xdc] = :op_call_c_a16
    t[0xC9] = :op_ret
    t[0xC0] = :op_ret_nz
    t[0xC8] = :op_ret_z
    t[0xD0] = :op_ret_nc
    t[0xD8] = :op_ret_c
    [0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF].each { |op| t[op] = :op_rst }
    [0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x3E].each { |op| t[op] = :op_ld_r8_d8 }
    t[0x36] = :op_ld_hl_d8
    (0x40..0x7F).each { |op| t[op] = :op_ld_r8_r8 }
    t[0x76] = :op_halt # override: HALT prime sur le range générique LD r8,r8
    t[0x10] = :op_stop
    [0x01, 0x11, 0x21, 0x31].each { |op| t[op] = :op_ld_rr_d16 }
    t[0xF8] = :op_ld_hl_sp_r8
    t[0xF9] = :op_ld_sp_hl
    t[0x02] = :op_ld_bc_a
    t[0x12] = :op_ld_de_a
    t[0x22] = :op_ldi_hl_a
    t[0x32] = :op_ldd_hl_a
    t[0x0A] = :op_ld_a_bc
    t[0x1A] = :op_ld_a_de
    t[0x2A] = :op_ldi_a_hl
    t[0x3A] = :op_ldd_a_hl
    t[0x08] = :op_ld_a16_sp
    t[0xEA] = :op_ld_a16_a
    t[0xFA] = :op_ld_a_a16
    t[0xE0] = :op_ldh_a8_a
    t[0xF0] = :op_ldh_a_a8
    t[0xE2] = :op_ldh_c_a
    t[0xF2] = :op_ldh_a_c
    [0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x3D].each { |op| t[op] = :op_dec_r8 }
    [0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x3C].each { |op| t[op] = :op_inc_r8 }
    [0x03, 0x13, 0x23, 0x33].each { |op| t[op] = :op_inc_rr }
    [0x34, 0x35].each { |op| t[op] = :op_inc_dec_hl }
    [0xb, 0x1b, 0x2b, 0x3b].each { |op| t[op] = :op_dec_rr }
    (0x80..0x87).each { |op| t[op] = :op_add_a_r8 }
    [0x09, 0x19, 0x29, 0x39].each { |op| t[op] = :op_add_hl_rr }
    t[0xE8] = :op_add_sp_r8
    (0x90..0x97).each { |op| t[op] = :op_sub_a_r8 }
    (0x88..0x8F).each { |op| t[op] = :op_adc_a_r8 }
    t[0xC6] = :op_add_a_d8
    t[0xCE] = :op_adc_a_d8
    (0x98..0x9F).each { |op| t[op] = :op_sbc_a_r8 }
    t[0xD6] = :op_sub_a_d8
    t[0xDE] = :op_sbc_a_d8
    t[0x27] = :op_daa
    (0xA0..0xA7).each { |op| t[op] = :op_and_a_r8 }
    t[0xE6] = :op_and_a_d8
    (0xB0..0xB7).each { |op| t[op] = :op_or_a_r8 }
    t[0xF6] = :op_or_a_d8
    (0xA8..0xAF).each { |op| t[op] = :op_xor_a_r8 }
    t[0xEE] = :op_xor_a_d8
    t[0x2F] = :op_cpl
    t[0x37] = :op_scf
    t[0x3F] = :op_ccf
    (0xB8..0xBF).each { |op| t[op] = :op_cp_a }
    t[0xFE] = :op_cp_a
    [0xC5, 0xD5, 0xE5].each { |op| t[op] = :op_push_rr }
    t[0xF5] = :op_push_af
    [0xC1, 0xD1, 0xE1].each { |op| t[op] = :op_pop_rr }
    t[0xF1] = :op_pop_af
    t[0x20] = :op_jr_nz_r8
    t[0x28] = :op_jr_z_r8
    t[0x30] = :op_jr_nc_r8
    t[0x38] = :op_jr_c_r8
    t[0x18] = :op_jr_r8
    t[0xCB] = :op_prefix_cb
  end.freeze

  def initialize(mmu, logger: nil)
    @logger = logger
    @mmu = mmu

    @infinite_loop = false
    @running = true
    @halted = { value: false, ime: false, stopped: false }

    @opcodes_with_micro_ops = {}

    # Utilisé pour stocker des opérations différées
    # ex: EI prend effet après l'instruction suivante
    @pending_operations = []

    # Registres spéciaux
    self.pc = 0x100 # point d'entrée standard des ROMs GB
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

    build_opcodes_with_micro_ops

    load_config

    @opcode_handlers = OPCODE_DISPATCH.map { |sym| method(sym) }.freeze
  end

  def build_opcode(opcode, name)
    micro_op = MicroOp.new(name, self)
    micro_op = yield(micro_op) if block_given?
    @opcodes_with_micro_ops[opcode] = micro_op
  end

  def build_opcodes_with_micro_ops
    build_opcode(0xc3, 'JP a16') { _1.read_next_address.jump_to_next_address }
    build_opcode(0x10, 'STOP', &:stop)
    # TODO: ajouter tous les autres opcodes avec des micro-ops
  end

  def load_config
    @config = Config.new(
      use_micro_ops: ENV['USE_MICRO_OPS'] == 'true'
    )
  end

  def_delegators :mmu, :read, :read_16, :write, :write_16

  def read_next_address
    mmu.read_16(@pc + 1)
  end

  # Retourne le nombre de cycles consommés
  def call_opcode(return_address, target_address = nil, condition: true)
    unless condition
      self.pc += 3
      return 12
    end

    # Pop next address, for future RET
    @sp = (@sp - 2) & 0xFFFF
    write_16(@sp, return_address)
    # Jump
    self.pc = target_address || read_next_address

    24
  end

  def ret_opcode(condition: true)
    unless condition
      self.pc += 1
      return 8
    end

    popped = read_16(@sp)
    self.pc = popped
    @sp = (@sp + 2) & 0xFFFF

    20
  end

  def pc=(value)
    @pc = value % 0x10000
  end

  def step
    execute_pending_operations

    opcode = mmu.read(@pc)
    @logger&.debug { "Executing opcode #{opcode_name(opcode)} at 0x#{@pc.to_s(16)}" }

    nb_cycles = process_opcode(opcode)
    process_timers(nb_cycles)
    nb_cycles + process_interrupts
  end

  def execute_pending_operations
    return if @pending_operations.empty?

    @pending_operations.each(&:call)
    @pending_operations.clear
  end

  def process_opcode(opcode)
    return handle_halt if @halted[:value]

    if config.use_micro_ops && (micro_op = opcodes_with_micro_ops[opcode])
      micro_op.execute
    else
      process_opcode_legacy(opcode)
    end
  end

  def process_opcode_legacy(opcode)
    nb_cycles = @opcode_handlers[opcode].call(opcode)
    display_state
    nb_cycles
  end

  def op_nop(_opcode)
    self.pc += 1
    4
  end

  def op_rotate_a(opcode)
    rotate_a_opcode(opcode)
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
    mmu.interrupts_enabled = false
    self.pc += 1
    4
  end

  def op_ei(_opcode)
    # EI ne prend effet qu'après l'instruction suivante
    @pending_operations << -> { mmu.interrupts_enabled = true }
    self.pc += 1
    4
  end

  def op_reti(_opcode)
    ret_opcode
    mmu.interrupts_enabled = true
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

  def op_ld_r8_d8(opcode)
    reg_index = (opcode - 0x06) / 8
    write_register_8(reg_index, read(@pc + 1))
    self.pc += 2
    8
  end

  def op_ld_hl_d8(_opcode)
    write(hl, read(@pc + 1))
    self.pc += 2
    8
  end

  def op_halt(_opcode)
    @logger&.debug { "HALT instruction encountered at #{@pc.to_s(16)}. Pausing CPU until an interrupt is served." }
    @halted[:value] = true
    @halted[:ime] = mmu.interrupts_enabled
    self.pc += 1
    4
  end

  def op_stop(_opcode)
    @logger&.debug { "STOP instruction encountered at #{@pc.to_s(16)}. Pausing CPU until joypad is triggered." }
    @halted[:value] = true
    @halted[:stopped] = true
    self.pc += 2
    0
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

  def op_dec_r8(opcode)
    reg_index = (opcode - 0x05) / 8
    new_value = (read_register_8(reg_index) - 1) & 0xFF
    write_register_8(reg_index, new_value)
    self.flag_z = new_value.zero?
    self.flag_h = (new_value & 0xF) == 0xF
    self.flag_n = true
    self.pc += 1
    4
  end

  def op_inc_r8(opcode)
    reg_index = (opcode - 0x04) / 8
    new_value = (read_register_8(reg_index) + 1) & 0xFF
    write_register_8(reg_index, new_value)
    self.flag_z = new_value.zero?
    self.flag_h = (new_value & 0xF).zero?
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
    self.flag_z = (result & 0xFF).zero?
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
    self.flag_z = (result & 0xFF).zero?
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
    self.flag_z = (result & 0xFF).zero?
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
    self.flag_z = (result & 0xFF) == 0
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
    self.flag_z = (result & 0xFF) == 0
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
    self.flag_z = (result & 0xFF) == 0
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
    self.flag_z = (result & 0xFF) == 0
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
    self.flag_z = (result & 0xFF) == 0
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
    self.flag_z = (result & 0xFF) == 0
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

  def op_prefix_cb(_opcode)
    cb_opcode = read(@pc + 1)
    nb_cycles = process_cb_opcode(cb_opcode)
    self.pc += 2
    nb_cycles
  end

  def op_unknown(opcode)
    handle_unknown_opcode(opcode)
  end

  # Advance cycles until next interrupt
  def handle_halt
    1 # tick only once
  end

  def process_timers(nb_cycles)
    mmu.increment_timers(nb_cycles)
  end

  def process_interrupts
    return 0 unless mmu.interrupts_enabled || @halted[:value]

    # Gère le STOP (reveil sur input)
    if @halted[:value] && @halted[:stopped]
      return 0 unless mmu.any_interrupt_requested?

      @halted[:value] = false
      return 0
    end

    return 0 unless mmu.pending_interrupts?

    # Gère le HALT
    if !@halted[:ime] && @halted[:value] # on skip l'interruption handler si HALT et IME=0
      @halted[:value] = false
      return 0
    end
    @halted[:value] = false

    # trouve la requete d'interruption la plus prioritaire
    interrupt = mmu.most_important_interrupt
    return 0 if interrupt.nil?

    # passe IME à 0 et efface la requete d'interruption (évite inter. imbriquées)
    mmu.interrupts_enabled = false
    mmu.clear_interrupt_requested(interrupt)

    # appelle le handler ; le coût en cycles du dispatch (non compté dans l'opcode qui l'a déclenché)
    # doit être répercuté sur le driving loop (PPU/APU/timers), sinon leur horloge dérive à chaque interruption.
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

  def handle_unknown_opcode(opcode)
    @running = false
    raise UnknownOpcode, "Unknown opcode #{opcode&.to_s(16)} (#{opcode.inspect}) at #{@pc.to_s(16)}"
  end

  def display_state
    return if infinite_loop

    @logger&.debug { "  PC: 0x#{@pc.to_s(16)}, A: #{a.to_s(16)}, BC: #{bc.to_s(16)}, DE: #{de.to_s(16)}, HL: #{hl.to_s(16)}" }
  end

  def opcode_name(opcode)
    r8 = ->(i) { %w[B C D E H L (HL) A][i] }

    case opcode
    when 0x00 then 'NOP'
    when 0x76 then 'HALT'
    when 0x10 then 'STOP'

    # LD r8,d8
    when 0x06 then 'LD B,d8'
    when 0x0E then 'LD C,d8'
    when 0x16 then 'LD D,d8'
    when 0x1E then 'LD E,d8'
    when 0x26 then 'LD H,d8'
    when 0x2E then 'LD L,d8'
    when 0x36 then 'LD (HL),d8'
    when 0x3E then 'LD A,d8'

    # LD rr,d16
    when 0x01 then 'LD BC,d16'
    when 0x11 then 'LD DE,d16'
    when 0x21 then 'LD HL,d16'
    when 0x31 then 'LD SP,d16'
    when 0xF8 then 'LD HL,SP+r8'
    when 0xF9 then 'LD SP,HL'

    # LD r8,r8
    when 0x40..0x7F
      dst = r8.call((opcode - 0x40) / 8)
      src = r8.call((opcode - 0x40) % 8)
      "LD #{dst},#{src}"

    # LD (rr),A / LD A,(rr)
    when 0x02 then 'LD (BC),A'
    when 0x12 then 'LD (DE),A'
    when 0x22 then 'LDI (HL),A'
    when 0x32 then 'LDD (HL),A'
    when 0x0A then 'LD A,(BC)'
    when 0x1A then 'LD A,(DE)'
    when 0x2A then 'LDI A,(HL)'
    when 0x3A then 'LDD A,(HL)'
    when 0xEA then 'LD (a16),A'
    when 0xFA then 'LD A,(a16)'
    when 0x08 then 'LD (a16),SP'

    # INC r8
    when 0x04 then 'INC B'
    when 0x0C then 'INC C'
    when 0x14 then 'INC D'
    when 0x1C then 'INC E'
    when 0x24 then 'INC H'
    when 0x2C then 'INC L'
    when 0x34 then 'INC (HL)'
    when 0x3C then 'INC A'

    # DEC r8
    when 0x05 then 'DEC B'
    when 0x0D then 'DEC C'
    when 0x15 then 'DEC D'
    when 0x1D then 'DEC E'
    when 0x25 then 'DEC H'
    when 0x2D then 'DEC L'
    when 0x35 then 'DEC (HL)'
    when 0x3D then 'DEC A'

    # INC/DEC rr
    when 0x03 then 'INC BC'
    when 0x13 then 'INC DE'
    when 0x23 then 'INC HL'
    when 0x33 then 'INC SP'
    when 0x0B then 'DEC BC'
    when 0x1B then 'DEC DE'
    when 0x2B then 'DEC HL'
    when 0x3B then 'DEC SP'

    # ALU A,r8
    when 0x80..0x87 then "ADD A,#{r8.call(opcode - 0x80)}"
    when 0x88..0x8F then "ADC A,#{r8.call(opcode - 0x88)}"
    when 0x90..0x97 then "SUB A,#{r8.call(opcode - 0x90)}"
    when 0x98..0x9F then "SBC A,#{r8.call(opcode - 0x98)}"
    when 0xA0..0xA7 then "AND A,#{r8.call(opcode - 0xA0)}"
    when 0xA8..0xAF then "XOR A,#{r8.call(opcode - 0xA8)}"
    when 0xB0..0xB7 then "OR A,#{r8.call(opcode - 0xB0)}"
    when 0xB8..0xBF then "CP A,#{r8.call(opcode - 0xB8)}"

    # ALU A,d8
    when 0xC6 then 'ADD A,d8'
    when 0xCE then 'ADC A,d8'
    when 0xD6 then 'SUB A,d8'
    when 0xDE then 'SBC A,d8'
    when 0xE6 then 'AND A,d8'
    when 0xF6 then 'OR A,d8'
    when 0xFE then 'CP A,d8'

    # ADD HL,rr
    when 0x09 then 'ADD HL,BC'
    when 0x19 then 'ADD HL,DE'
    when 0x29 then 'ADD HL,HL'
    when 0x39 then 'ADD HL,SP'
    when 0xE8 then 'ADD SP,r8'

    # PUSH/POP
    when 0xC5 then 'PUSH BC'
    when 0xD5 then 'PUSH DE'
    when 0xE5 then 'PUSH HL'
    when 0xF5 then 'PUSH AF'
    when 0xC1 then 'POP BC'
    when 0xD1 then 'POP DE'
    when 0xE1 then 'POP HL'
    when 0xF1 then 'POP AF'

    # JP
    when 0xC3 then 'JP a16'
    when 0xC2 then 'JP NZ,a16'
    when 0xCA then 'JP Z,a16'
    when 0xD2 then 'JP NC,a16'
    when 0xDA then 'JP C,a16'
    when 0xE9 then 'JP HL'

    # JR
    when 0x18 then 'JR r8'
    when 0x20 then 'JR NZ,r8'
    when 0x28 then 'JR Z,r8'
    when 0x30 then 'JR NC,r8'
    when 0x38 then 'JR C,r8'

    # CALL
    when 0xCD then 'CALL a16'
    when 0xC4 then 'CALL NZ,a16'
    when 0xCC then 'CALL Z,a16'
    when 0xD4 then 'CALL NC,a16'
    when 0xDC then 'CALL C,a16'

    # RET
    when 0xC9 then 'RET'
    when 0xC0 then 'RET NZ'
    when 0xC8 then 'RET Z'
    when 0xD0 then 'RET NC'
    when 0xD8 then 'RET C'
    when 0xD9 then 'RETI'

    # RST
    when 0xC7 then 'RST 0x00'
    when 0xCF then 'RST 0x08'
    when 0xD7 then 'RST 0x10'
    when 0xDF then 'RST 0x18'
    when 0xE7 then 'RST 0x20'
    when 0xEF then 'RST 0x28'
    when 0xF7 then 'RST 0x30'
    when 0xFF then 'RST 0x38'

    # LDH
    when 0xE0 then 'LDH (a8),A'
    when 0xF0 then 'LDH A,(a8)'
    when 0xE2 then 'LDH (C),A'
    when 0xF2 then 'LDH A,(C)'

    # Interrupts
    when 0xF3 then 'DI'
    when 0xFB then 'EI'

    # Rotate A
    when 0x07 then 'RLCA'
    when 0x0F then 'RRCA'
    when 0x17 then 'RLA'
    when 0x1F then 'RRA'

    # CPL
    when 0x2F then 'CPL'

    # SCF/CCF
    when 0x37 then 'SCF'
    when 0x3F then 'CCF'

    # PREFIX CB
    when 0xCB then 'PREFIX CB'

    else "UNKNOWN ⚠️ (0x#{opcode.to_s(16).upcase})"
    end
  end

  def running?
    @running
  end
end
