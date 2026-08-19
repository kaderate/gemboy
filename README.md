# Gemboy, a Game Boy emulator written in Ruby

[![coverage report](https://gitlab.com/abk/emu-gb/badges/main/coverage.svg)](https://gitlab.com/abk/emu-gb/-/jobs/artifacts/main/file/coverage/index.html?job=test)

```
   ________________________________
  |   .------------------------.   |    G E M B O Y
  |   | .--------------------.  |  |    ═══════════════════════
  |   | |                    |  |  |
  |   | |       _/\/\_       |  |  |    A Game Boy emulator
  |   | |      /◆◉  ◉◆\      |  |  |    written in Ruby.
  |   | |     /◆◆  ᴗ ◆◆\     |  |  |
  |   | |     \◆◆◆◆◆◆◆ /     |  |  |    Because C was too
  |   | |       \/\/\/       |  |  |    reasonable.
  |   | |                    |  |  |
  |   | '--------------------'  /  |
  |   '-----------------------./   |    Tetris runs. Surprisingly.
  |    Ninxxxdo GEMBOY             |
  |                          _     |
  |         _            _  (_)    |
  |       _| |_         (_)  A     |
  |      |_   _|         B         |
  |        |_|                     |
  |                                |
  |      _,=^    _,=^      ..\\    |
  |     SELECT  START     \\\\\\  /
  |                       \\\.. _/
  |_____________________________'
```

Gemboy is a Game Boy DMG-01 (original model) emulator written in Ruby.

Gemboy runs original Game Boy ROMs: SM83 CPU, memory banking, scanline-accurate graphics,
four-channel stereo sound and battery saves.

## Features

- **CPU**: full SM83 instruction set, interrupts, `HALT`/`STOP`, per-instruction cycle counts
- **Cartridges**: ROM only, MBC1, MBC3 (with real time clock) and MBC5, with `.sav` persistence
  for battery-backed games
- **Graphics**: background, window and sprites, rendered dot by dot with the real PPU mode cycle
- **Sound**: the four DMG channels, stereo panning and master volume
- **Input**: full joypad
- **Accuracy**: passes Blargg's `cpu_instrs` suite and renders `dmg-acid2` pixel-perfect

## Prerequisites

- Ruby 3.3+
- SDL2 and SDL2_ttf:
  - **macOS**: `brew install sdl2 sdl2_ttf`
  - **Linux**: `apt install libsdl2-dev libsdl2-ttf-dev`

If the libraries live somewhere unusual, point `GEMBOY_SDL_DIR` at the directory holding them.

## Installation

```bash
git clone https://github.com/kaderate/gemboy.git
cd gemboy
bundle install
bundle exec rspec   # optional, verifies the setup
```

## Running

```bash
bin/gemboy path/to/rom.gb
```

On macOS you can omit the path: a file picker opens. `bundle exec ruby lib/emugb.rb <rom>`
does the same thing if you prefer going through Bundler.

Battery-backed games write their save next to the ROM as a `.sav` file, on exit and on every
cartridge RAM write.

### Input mapping

| Game Boy | Keyboard |
|---|---|
| D-Pad | Arrow keys |
| A | Z |
| B | X |
| Start | Enter |
| Select | Space |

## Development

```bash
bundle exec rspec                                          # test suite
bundle exec rubocop                                        # linter
ruby test_roms/run_test.rb <rom.gb> <out.png>              # one test ROM, headless + screenshot
ruby test_roms/run_all.rb                                  # HTML report over every suite
```

`test_roms/` holds the reference suites (Blargg, dmg-acid2, mealybug). They run headless and
report either through the serial port or by exporting the final framebuffer as a PNG.

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the emulator is built, the design decisions
behind it, and performance notes.

## References

- [Pan Docs](https://gbdev.io/pandocs/) — Game Boy technical reference
- [CPU opcode list](https://izik1.github.io/gbops/)
- [Blargg's test ROMs](https://github.com/retrio/gb-test-roms)
- [dmg-acid2](https://github.com/mattcurrie/dmg-acid2) — PPU rendering test

## License

MIT, see [LICENSE](LICENSE). The bundled Inter font is under the SIL Open Font License, see
[assets/fonts/LICENSE-Inter.txt](assets/fonts/LICENSE-Inter.txt).

## Contributing

Contributions are welcome! Feel free to:
- Open issues for bugs or feature requests
- Submit pull requests with improvements
- Share ideas for optimization or compatibility enhancements

Please ensure tests pass before submitting PRs:
```bash
bundle exec rspec
```
