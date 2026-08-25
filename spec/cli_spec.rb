require_relative '../lib/cli'

RSpec.describe CLI do
  def stub_host_os(host_os)
    stub_const('RbConfig::CONFIG', RbConfig::CONFIG.merge('host_os' => host_os))
  end

  before do
    allow(Engine).to receive_messages(new: :built)
    allow(described_class).to receive(:puts)
  end

  describe '.build_with_rom' do
    it 'uses the single CLI argument as the ROM path' do
      stub_const('ARGV', ['  roms/tetris.gb  '])

      expect(described_class.build_with_rom).to eq(:built)
      expect(Engine).to have_received(:new).with('roms/tetris.gb', debug_port: nil)
    end

    it 'enables the debug server on the default port' do
      stub_const('ARGV', ['--debug-server', 'roms/tetris.gb'])

      described_class.build_with_rom

      expect(Engine).to have_received(:new).with('roms/tetris.gb', debug_port: Debug::DEFAULT_PORT)
    end

    it 'enables the debug server on an explicit port' do
      stub_const('ARGV', ['--debug-server=4242', 'roms/tetris.gb'])

      described_class.build_with_rom

      expect(Engine).to have_received(:new).with('roms/tetris.gb', debug_port: 4242)
    end

    it 'exits with status 1 when given more than one argument' do
      stub_const('ARGV', %w[first second])

      expect { described_class.build_with_rom }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end

    it 'shows the usage instead of opening a dialog on non-macOS' do
      stub_const('ARGV', [])
      stub_host_os('linux-gnu')

      expect { described_class.build_with_rom }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end

    context 'with the macOS file picker' do
      before { stub_host_os('darwin24') }

      it 'uses the selected path' do
        stub_const('ARGV', [])
        allow(described_class).to receive(:`).and_return("/tmp/zelda.gb\n")

        described_class.build_with_rom

        expect(Engine).to have_received(:new).with('/tmp/zelda.gb', debug_port: nil)
      end

      it 'exits with status 0 when the dialog is cancelled' do
        stub_const('ARGV', [])
        allow(described_class).to receive(:`).and_return("\n")

        expect { described_class.build_with_rom }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      end
    end
  end
end
