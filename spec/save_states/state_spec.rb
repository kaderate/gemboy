# frozen_string_literal: true

require 'logger'

require_relative '../../lib/save_states/state'

RSpec.describe SaveStates::State do
  subject(:bytes) { described_class.dump(motherboard, cartridge) }

  let(:cartridge) { build_cartridge(rom: build_rom(bytes: [0x00], at: 0x100)) }
  let(:motherboard) { Motherboard.build(cartridge) }

  describe '.dump' do
    it 'starts with a one-line JSON header describing the state' do
      allow(Time).to receive(:now).and_return(Time.at(1_757_250_000))

      expect(described_class.read_header(bytes)).to include('magic' => 'GEMBOY-STATE',
                                                            'format' => described_class::FORMAT,
                                                            'rom' => cartridge.name,
                                                            'saved_at' => 1_757_250_000)
    end

    it 'leaves the ROM out of the payload' do
      big_rom = build_cartridge(rom: build_rom(bank_count: 8))
      small_rom = build_cartridge(rom: build_rom(bank_count: 2))

      expect(described_class.dump(Motherboard.build(big_rom), big_rom).bytesize)
        .to eq(described_class.dump(Motherboard.build(small_rom), small_rom).bytesize)
    end
  end

  describe '.load' do
    it 'round-trips the emulated state' do
      motherboard.mmu.write(0xC000, 0x42)
      motherboard.cpu.pc = 0x1234

      loaded = described_class.load(described_class.dump(motherboard, cartridge), cartridge)

      expect(loaded.mmu.read(0xC000)).to eq(0x42)
      expect(loaded.cpu.pc).to eq(0x1234)
    end

    it 'reattaches the ROM of the running cartridge' do
      loaded = described_class.load(bytes, cartridge)

      expect(loaded.mmu.mbc.rom).to be(cartridge.rom_bytes)
    end

    it 'reattaches the given logger' do
      logger = Logger.new(File::NULL).tap { _1.formatter = proc { |_s, _dt, _p, msg| msg } }

      loaded = described_class.load(described_class.dump(Motherboard.build(cartridge, logger:), cartridge), cartridge,
                                    logger:)

      expect(loaded.cpu.instance_variable_get(:@logger)).to be(logger)
    end

    it 'keeps the loaded CPU executable' do
      loaded = described_class.load(bytes, cartridge)
      loaded.cpu.pc = 0x100

      expect { loaded.cpu.step }.not_to raise_error
    end

    # Marshal restores ivars, it does not re-run #initialize: a component holding state derived in
    # its constructor comes back with that state missing, and only blows up once ticked.
    it 'keeps the loaded PPU, APU and timer tickable' do
      motherboard.mmu.write(0xFF26, 0x80) # NR52: APU on
      motherboard.mmu.write(0xFF14, 0x80) # NR14: trigger pulse channel 1
      motherboard.mmu.write(0xFF07, 0x05) # TAC: timer enabled, 16 cycles per increment

      loaded = described_class.load(described_class.dump(motherboard, cartridge), cartridge)
      loaded.cpu.pc = 0x100

      expect { loaded.run_steps(500) }.not_to raise_error
    end

    it 'rejects bytes that are not a save state' do
      expect { described_class.load('not a save state', cartridge) }
        .to raise_error(SaveStates::UnreadableState)
    end

    it 'rejects a truncated payload' do
      expect { described_class.load(bytes.byteslice(0, bytes.bytesize - 10), cartridge) }
        .to raise_error(SaveStates::UnreadableState)
    end

    it 'rejects a state written by another format version' do
      state = bytes
      stub_const('SaveStates::State::FORMAT', described_class::FORMAT + 1)

      expect { described_class.load(state, cartridge) }.to raise_error(SaveStates::IncompatibleVersion)
    end

    it 'rejects a state saved from another ROM' do
      other_cartridge = build_cartridge(rom: build_rom(bytes: [0xFF], at: 0x100))

      expect { described_class.load(bytes, other_cartridge) }.to raise_error(SaveStates::ROMMismatch)
    end
  end

  describe '.read_header' do
    it 'reads the header from the first line alone' do
      header_line = bytes.byteslice(0, bytes.index("\n"))

      expect(described_class.read_header(header_line)).to include('magic' => 'GEMBOY-STATE')
    end

    it 'rejects a first line that is not JSON' do
      expect { described_class.read_header("nope\nrest") }.to raise_error(SaveStates::UnreadableState)
    end
  end
end
