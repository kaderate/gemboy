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

  attr_reader :pc, :mmu, :interrupts, :timer, :infinite_loop
  attr_accessor :registers, :sp, :halted, :ime

  def initialize(mmu, interrupts: Interrupts.new, timer: Timer.new, logger: nil)
    @logger = logger
    @mmu = mmu
    @interrupts = interrupts
    @timer = timer

    @infinite_loop = false
    @running = true
    @halted = { value: false, ime: false, stopped: false }

    @ime = false

    # Used to store the pending operations
    # ex: EI takes effect after the following instruction
    @pending_operations = []

    # Special registers
    self.pc = 0x100 # standard entry point for GB ROMs
    @sp = 0xFFFE

    # General registers
    @registers = BootValues::REGISTERS_ROM_BOOT_VALUES.dup

    build_opcodes
  end

  def build_opcodes
    @opcode_handlers = OPCODE_DISPATCH.map { |sym| method(sym) }.freeze
  end

  def_delegators :mmu, :read, :read_16, :write, :write_16

  def read_next_address = mmu.read_16(@pc + 1)

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

    nb_cycles = @opcode_handlers[opcode].call(opcode)
    display_state
    nb_cycles
  end

  # Advance cycles until next interrupt
  def handle_halt
    4 # ticks
  end

  def process_timers(nb_cycles)
    require_timer_interrupt = timer.tick!(nb_cycles)
    interrupts.request(:timer) if require_timer_interrupt
  end

  def process_interrupts
    return 0 unless @ime || @halted[:value]

    # Gère le STOP (reveil sur input)
    if @halted[:value] && @halted[:stopped]
      return 0 unless interrupts.any_requested?

      @halted[:value] = false
      return 0
    end

    return 0 unless interrupts.pending?

    # Gère le HALT
    if !@halted[:ime] && @halted[:value] # on skip l'interruption handler si HALT et IME=0
      @halted[:value] = false
      return 0
    end
    @halted[:value] = false

    # trouve la requete d'interruption la plus prioritaire
    interrupt = interrupts.most_important(@ime)
    return 0 if interrupt.nil?

    # passe IME à 0 et efface la requete d'interruption (évite inter. imbriquées)
    @ime = false
    interrupts.clear_requested(interrupt)

    # appelle le handler ; le coût en cycles du dispatch (non compté dans l'opcode qui l'a déclenché)
    # doit être répercuté sur le driving loop (PPU/APU/timers), sinon leur horloge dérive à chaque interruption.
    call_opcode(@pc, interrupts.vector(interrupt))
    # RETI reprend l'exécution (pop PC de la stack et set IME à 1)
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
