# frozen_string_literal: true
# Instant save/restore of a full emulator state, so scripted exploration doesn't have to replay
# the ~150s boot+intro sequence from scratch every run (measured: 86s boot, 53s intro dialogue).
#
# Two fields resist Marshal directly: APU's @audio_queue (a Thread::Queue, headless scripts don't
# need real audio output) and CPU's @opcode_handlers (an array of bound Method objects, which is
# pure derived state -- CPU#build_opcodes regenerates it identically from OPCODE_DISPATCH). Both
# are nil'd out before dumping and restored/rebuilt after loading; nothing else in the object
# graph needed special handling.
module Zelda
  module Checkpoint
    def self.save(path, cpu:, ppu:, apu:, mmu:, keys:)
      audio_queue = apu.instance_variable_get(:@audio_queue)
      opcode_handlers = cpu.instance_variable_get(:@opcode_handlers)
      apu.instance_variable_set(:@audio_queue, nil)
      cpu.instance_variable_set(:@opcode_handlers, nil)
      File.binwrite(path, Marshal.dump({ cpu:, ppu:, apu:, mmu:, keys: }))
    ensure
      apu.instance_variable_set(:@audio_queue, audio_queue)
      cpu.instance_variable_set(:@opcode_handlers, opcode_handlers)
    end

    def self.load(path)
      state = Marshal.load(File.binread(path))
      state[:cpu].build_opcodes
      state[:apu].instance_variable_set(:@audio_queue, Thread::Queue.new)
      [state[:cpu], state[:ppu], state[:apu], state[:mmu], state[:keys]]
    end
  end
end
