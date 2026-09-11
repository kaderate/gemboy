require 'forwardable'
require 'logger'
require_relative 'cpu/register_accessors'
require_relative 'cpu/opcode_dispatch'
require_relative 'cpu/opcodes/loads'
require_relative 'cpu/opcodes/alu'
require_relative 'cpu/opcodes/control_flow'
require_relative 'cpu/opcodes/cb'
require_relative 'cpu/disassembler'
require_relative 'boot_values'
require_relative 'interrupts'
require_relative 'timer'
require_relative 'speed_shift'
require_relative 'model_selector'

# GameBoy DMG-01 CPU Emulator en Ruby
class CPU
  extend Forwardable

  T_CYCLES_PER_SECOND = 4_194_304

  class UnknownOpcode < StandardError; end

  include CPU::RegisterAccessors
  include CPU::OpcodeDispatch
  include CPU::Opcodes::Loads
  include CPU::Opcodes::Alu
  include CPU::Opcodes::ControlFlow
  include CPU::Opcodes::Cb
  include CPU::Disassembler

  attr_reader :pc, :mmu, :interrupts, :timer, :speed_shift, :model, :infinite_loop
  attr_accessor :registers, :sp, :halted, :ime

  # rubocop:disable-next Metrics/ParameterLists
  def initialize(mmu, interrupts: Interrupts.new, timer: Timer.new, speed_shift: SpeedShift.new,
                 model: ModelSelector::NullModel.new, logger: nil)
    @logger = logger
    @mmu = mmu
    @interrupts = interrupts
    @timer = timer
    @speed_shift = speed_shift
    @model = model

    # Internal state
    @infinite_loop = false
    @running = true
    @halted = { value: false, ime: false, stopped: false }
    @ime = false

    # Used to store the pending operations (EI takes effect after the following instruction)
    @pending_operations = []

    # Special registers
    self.pc = 0x100 # standard entry point for GB ROMs
    @sp = 0xFFFE

    # General registers
    @registers = BootValues.registers_for(model.model_name)

    build_opcodes
  end

  def build_opcodes
    @opcode_handlers = OPCODE_DISPATCH.map { |sym| opcode_handler(sym) }.freeze
  end

  def opcode_handler(sym)
    case sym
    when :op_unknown then ->(opcode) { op_unknown(opcode) }
    when :op_nop then ->(opcode) { op_nop(opcode) }
    when :op_rotate_a then ->(opcode) { op_rotate_a(opcode) }
    when :op_jp_a16 then ->(opcode) { op_jp_a16(opcode) }
    when :op_jp_nz_a16 then ->(opcode) { op_jp_nz_a16(opcode) }
    when :op_jp_z_a16 then ->(opcode) { op_jp_z_a16(opcode) }
    when :op_jp_nc_a16 then ->(opcode) { op_jp_nc_a16(opcode) }
    when :op_jp_c_a16 then ->(opcode) { op_jp_c_a16(opcode) }
    when :op_jp_hl then ->(opcode) { op_jp_hl(opcode) }
    when :op_di then ->(opcode) { op_di(opcode) }
    when :op_ei then ->(opcode) { op_ei(opcode) }
    when :op_reti then ->(opcode) { op_reti(opcode) }
    when :op_call_a16 then ->(opcode) { op_call_a16(opcode) }
    when :op_call_nz_a16 then ->(opcode) { op_call_nz_a16(opcode) }
    when :op_call_z_a16 then ->(opcode) { op_call_z_a16(opcode) }
    when :op_call_nc_a16 then ->(opcode) { op_call_nc_a16(opcode) }
    when :op_call_c_a16 then ->(opcode) { op_call_c_a16(opcode) }
    when :op_ret then ->(opcode) { op_ret(opcode) }
    when :op_ret_nz then ->(opcode) { op_ret_nz(opcode) }
    when :op_ret_z then ->(opcode) { op_ret_z(opcode) }
    when :op_ret_nc then ->(opcode) { op_ret_nc(opcode) }
    when :op_ret_c then ->(opcode) { op_ret_c(opcode) }
    when :op_rst then ->(opcode) { op_rst(opcode) }
    when :op_ld_r8_d8 then ->(opcode) { op_ld_r8_d8(opcode) }
    when :op_ld_hl_d8 then ->(opcode) { op_ld_hl_d8(opcode) }
    when :op_ld_r8_r8 then ->(opcode) { op_ld_r8_r8(opcode) }
    when :op_halt then ->(opcode) { op_halt(opcode) }
    when :op_stop then ->(opcode) { op_stop(opcode) }
    when :op_ld_rr_d16 then ->(opcode) { op_ld_rr_d16(opcode) }
    when :op_ld_hl_sp_r8 then ->(opcode) { op_ld_hl_sp_r8(opcode) }
    when :op_ld_sp_hl then ->(opcode) { op_ld_sp_hl(opcode) }
    when :op_ld_bc_a then ->(opcode) { op_ld_bc_a(opcode) }
    when :op_ld_de_a then ->(opcode) { op_ld_de_a(opcode) }
    when :op_ldi_hl_a then ->(opcode) { op_ldi_hl_a(opcode) }
    when :op_ldd_hl_a then ->(opcode) { op_ldd_hl_a(opcode) }
    when :op_ld_a_bc then ->(opcode) { op_ld_a_bc(opcode) }
    when :op_ld_a_de then ->(opcode) { op_ld_a_de(opcode) }
    when :op_ldi_a_hl then ->(opcode) { op_ldi_a_hl(opcode) }
    when :op_ldd_a_hl then ->(opcode) { op_ldd_a_hl(opcode) }
    when :op_ld_a16_sp then ->(opcode) { op_ld_a16_sp(opcode) }
    when :op_ld_a16_a then ->(opcode) { op_ld_a16_a(opcode) }
    when :op_ld_a_a16 then ->(opcode) { op_ld_a_a16(opcode) }
    when :op_ldh_a8_a then ->(opcode) { op_ldh_a8_a(opcode) }
    when :op_ldh_a_a8 then ->(opcode) { op_ldh_a_a8(opcode) }
    when :op_ldh_c_a then ->(opcode) { op_ldh_c_a(opcode) }
    when :op_ldh_a_c then ->(opcode) { op_ldh_a_c(opcode) }
    when :op_dec_r8 then ->(opcode) { op_dec_r8(opcode) }
    when :op_inc_r8 then ->(opcode) { op_inc_r8(opcode) }
    when :op_inc_rr then ->(opcode) { op_inc_rr(opcode) }
    when :op_inc_dec_hl then ->(opcode) { op_inc_dec_hl(opcode) }
    when :op_dec_rr then ->(opcode) { op_dec_rr(opcode) }
    when :op_add_a_r8 then ->(opcode) { op_add_a_r8(opcode) }
    when :op_add_hl_rr then ->(opcode) { op_add_hl_rr(opcode) }
    when :op_add_sp_r8 then ->(opcode) { op_add_sp_r8(opcode) }
    when :op_sub_a_r8 then ->(opcode) { op_sub_a_r8(opcode) }
    when :op_adc_a_r8 then ->(opcode) { op_adc_a_r8(opcode) }
    when :op_add_a_d8 then ->(opcode) { op_add_a_d8(opcode) }
    when :op_adc_a_d8 then ->(opcode) { op_adc_a_d8(opcode) }
    when :op_sbc_a_r8 then ->(opcode) { op_sbc_a_r8(opcode) }
    when :op_sub_a_d8 then ->(opcode) { op_sub_a_d8(opcode) }
    when :op_sbc_a_d8 then ->(opcode) { op_sbc_a_d8(opcode) }
    when :op_daa then ->(opcode) { op_daa(opcode) }
    when :op_and_a_r8 then ->(opcode) { op_and_a_r8(opcode) }
    when :op_and_a_d8 then ->(opcode) { op_and_a_d8(opcode) }
    when :op_or_a_r8 then ->(opcode) { op_or_a_r8(opcode) }
    when :op_or_a_d8 then ->(opcode) { op_or_a_d8(opcode) }
    when :op_xor_a_r8 then ->(opcode) { op_xor_a_r8(opcode) }
    when :op_xor_a_d8 then ->(opcode) { op_xor_a_d8(opcode) }
    when :op_cpl then ->(opcode) { op_cpl(opcode) }
    when :op_scf then ->(opcode) { op_scf(opcode) }
    when :op_ccf then ->(opcode) { op_ccf(opcode) }
    when :op_cp_a then ->(opcode) { op_cp_a(opcode) }
    when :op_push_rr then ->(opcode) { op_push_rr(opcode) }
    when :op_push_af then ->(opcode) { op_push_af(opcode) }
    when :op_pop_rr then ->(opcode) { op_pop_rr(opcode) }
    when :op_pop_af then ->(opcode) { op_pop_af(opcode) }
    when :op_jr_nz_r8 then ->(opcode) { op_jr_nz_r8(opcode) }
    when :op_jr_z_r8 then ->(opcode) { op_jr_z_r8(opcode) }
    when :op_jr_nc_r8 then ->(opcode) { op_jr_nc_r8(opcode) }
    when :op_jr_c_r8 then ->(opcode) { op_jr_c_r8(opcode) }
    when :op_jr_r8 then ->(opcode) { op_jr_r8(opcode) }
    when :op_prefix_cb then ->(opcode) { op_prefix_cb(opcode) }
    else raise ArgumentError, "Unknown opcode handler: #{sym}"
    end
  end

  def_delegators :mmu, :read, :read_16, :write, :write_16

  def read_next_address = mmu.read_16(@pc + 1)

  def call_opcode(return_address, target_address = nil, condition: true)
    unless condition
      self.pc += 3
      return 12
    end

    @sp = (@sp - 2) & 0xFFFF
    write_16(@sp, return_address)
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
    t_cycles = process_opcode(opcode)
    process_timers(t_cycles)
    t_cycles + process_interrupts
  end

  def execute_pending_operations
    return if @pending_operations.empty?

    @pending_operations.each(&:call)
    @pending_operations.clear
  end

  def process_opcode(opcode)
    return handle_halt if @halted[:value]

    t_cycles = @opcode_handlers[opcode].call(opcode)
    display_state
    t_cycles
  end

  def handle_halt
    4
  end

  def process_timers(t_cycles)
    require_timer_interrupt = timer.tick!(t_cycles)
    interrupts.request(:timer) if require_timer_interrupt
  end

  def process_interrupts
    return 0 unless @ime || @halted[:value]

    if @halted[:value] && @halted[:stopped]
      return 0 unless interrupts.any_requested?

      @halted[:value] = false
      return 0
    end

    return 0 unless interrupts.pending?

    if !@halted[:ime] && @halted[:value]
      @halted[:value] = false
      return 0
    end

    @halted[:value] = false
    interrupt = interrupts.most_important(@ime)
    return 0 if interrupt.nil?

    @ime = false
    interrupts.clear_requested(interrupt)
    call_opcode(@pc, interrupts.vector(interrupt))
  end

  def handle_unknown_opcode(opcode)
    @running = false
    raise UnknownOpcode, "Unknown opcode #{opcode&.to_s(16)} (#{opcode.inspect}) at #{@pc.to_s(16)}"
  end

  def display_state
    return if infinite_loop

    @logger&.debug { "  PC: 0x#{@pc.to_s(16)}, A: #{a.to_s(16)}, BC: #{bc.to_s(16)}, DE: #{de.to_s(16)}, HL: #{hl.to_s(16)}" }
  end

  def running?
    @running
  end
end
