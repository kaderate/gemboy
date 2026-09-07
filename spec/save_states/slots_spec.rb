# frozen_string_literal: true

require 'tmpdir'

require_relative '../../lib/save_states/slots'

RSpec.describe SaveStates::Slots do
  subject(:slots) { described_class.new(cartridge) }

  around { |example| Dir.mktmpdir { |dir| @dir = dir and example.run } }

  let(:cartridge) do
    build_cartridge(rom: build_rom(bytes: [0x00], at: 0x100), with_battery: true, ram_bank_count: 1,
                    rom_path: File.join(@dir, 'game.gb'))
  end
  let(:motherboard) { Motherboard.build(cartridge) }

  describe '#path' do
    it 'names a slot file next to the ROM' do
      expect(slots.path(3)).to eq(File.join(@dir, 'game.s3'))
    end

    it 'rejects a slot outside the supported range' do
      expect { slots.path(0) }.to raise_error(SaveStates::UnknownSlot)
    end
  end

  describe '#save' do
    it 'writes a loadable state' do
      motherboard.cpu.pc = 0x1234
      slots.save(3, motherboard)

      expect(slots.load(3).cpu.pc).to eq(0x1234)
    end

    it 'overwrites an existing slot' do
      slots.save(3, motherboard)
      motherboard.cpu.pc = 0x4321
      slots.save(3, motherboard)

      expect(slots.load(3).cpu.pc).to eq(0x4321)
    end

    it 'leaves no temporary file behind' do
      slots.save(3, motherboard)

      expect(Dir.children(@dir)).to contain_exactly('game.s3')
    end
  end

  describe '#load' do
    it 'reports a slot that was never saved' do
      expect { slots.load(3) }.to raise_error(SaveStates::EmptySlot)
    end

    it 'propagates a state saved from another ROM' do
      slots.save(3, motherboard)
      other = described_class.new(build_cartridge(rom: build_rom(bytes: [0xFF], at: 0x100),
                                                  rom_path: File.join(@dir, 'game.gb')))

      expect { other.load(3) }.to raise_error(SaveStates::ROMMismatch)
    end
  end

  describe '#info' do
    it 'reports an empty slot' do
      expect(slots.info(3)).to have_attributes(slot: 3, saved_at: nil, exists?: false)
    end

    it 'reports the save date without deserializing the payload' do
      allow(Time).to receive(:now).and_return(Time.at(1_757_250_000))
      slots.save(3, motherboard)
      allow(SaveStates::State).to receive(:load).and_raise('payload must not be read')

      expect(slots.info(3)).to have_attributes(saved_at: Time.at(1_757_250_000), exists?: true)
    end

    it 'reports an unreadable slot as empty' do
      File.binwrite(slots.path(3), 'garbage')

      expect(slots.info(3)).to have_attributes(saved_at: nil, exists?: false)
    end
  end

  describe '#backup_battery_ram!' do
    it 'copies the .sav next to it' do
      File.binwrite(cartridge.battery_ram_path, 'save data')

      slots.backup_battery_ram!

      expect(File.binread("#{cartridge.battery_ram_path}.bak")).to eq('save data')
    end

    it 'does nothing when the cartridge has no battery' do
      no_battery = described_class.new(build_cartridge(rom_path: File.join(@dir, 'game.gb')))

      expect { no_battery.backup_battery_ram! }.not_to raise_error
    end

    it 'does nothing when no .sav exists yet' do
      expect { slots.backup_battery_ram! }.not_to(change { Dir.children(@dir) })
    end
  end
end
