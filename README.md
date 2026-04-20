# Gemboy, a Game Boy emulator written in Ruby

Gemboy is a Game Boy DMG-01 (original model) emulator written in Ruby.

This project implements a cycle-accurate CPU emulator, memory management unit (MMU), picture processing unit (PPU) for graphics rendering, and full input handling.

## Overview

This emulator faithfully reproduces the Game Boy hardware architecture, allowing you to run original Game Boy ROMs on modern systems. It features:

- **CPU Emulation**: Complete Z80-based processor with 8/16-bit registers, micro-operations for instruction decomposition
- **Memory Management**: Proper address space mapping (ROM, VRAM, WRAM, I/O registers, HRAM) with interrupt support
- **Graphics Pipeline**: Scanline-based rendering with PPU cycle tracking
- **Input Handling**: Full joypad support (D-pad, A/B buttons)
- **Thread-Safe Rendering**: Synchronized rendering loop between emulation thread and Gosu window

## Prerequisites

- Ruby 4.0+
- System libraries for Gosu:
  - **macOS**: Works out of the box (Xcode Command Line Tools recommended)
  - **Linux**: `libsdl2-dev libgl1-mesa-dev libpango1.0-dev libfontconfig1-dev libglib2.0-dev libgtk-3-dev` on Ubuntu/Debian
  - **Windows**: Works out of the box

## Installation & Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd emu-gb
```

2. Install dependencies:
```bash
bundle install
```

3. Verify installation (run tests):
```bash
bundle exec rspec
```

## Running the Emulator

Load and run a Game Boy ROM:

```bash
bundle exec ruby lib/emugb.rb path/to/your/rom.gb
```

### Input Mapping

| Game Boy Button | Keyboard |
|-----------------|----------|
| D-Pad (↑↓←→) | Arrow Keys |
| A Button | Z |
| B Button | X |
| Start | Enter |
| Select | Space |

## Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Game Boy Emulator                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐      ┌─────────┐      ┌──────────┐            │
│  │   CPU    │◄────►│   MMU   │◄────►│ Memory   │            │
│  │ (Z80)    │      │ (Address│      │ (ROM,    │            │
│  │          │      │  Mapper)│      │  VRAM,   │            │
│  │ - 8/16   │      │         │      │  WRAM)   │            │
│  │   bit    │      └─────────┘      └──────────┘            │
│  │   regs   │           ▲                                   │
│  │ - Flags  │           │                                   │
│  │ - PC/SP  │           │                                   │
│  └──────────┘      ┌────┴────┐      ┌──────────┐            │
│       ▲            │  Timers │      │  I/O     │            │
│       │            │ & IRQs  │      │ Registers│            │
│       │            └────┬────┘      └──────────┘            │
│  Cycles            ┌────┴──── ┐                             │
│                    │   PPU    │                             │
│               ┌───►│ (Graphic │◄───┐                        │
│               │    │ Pipeline)│    │                        │
│               │    └─────┬────┘    │                        │
│          Gosu Thread     │    Emulation Thread              │
│               │          │         │                        │
│               │    ┌─────▼────┐    │                        │
│               │    │  Screen  │    │                        │
│               └───►│ (Gosu::  │◄───┘                        │
│                    │  Window) │                             │
│                    └──────────┘                             │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │            KeyState (Input Handler)                  │   │
│  │  Monitors joypad state, synchronized with MMU        │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Component Details

#### 1. CPU (Central Processing Unit)

```
┌──────────────────────────────────────────┐
│            CPU (Z80-based)               │
├──────────────────────────────────────────┤
│                                          │
│  ┌────────────┐   ┌─────────────────┐    │
│  │ Registers  │   │ Program Counter │    │
│  ├────────────┤   │ (PC) = 0x100    │    │
│  │ A:0xFF     │   │ Stack Ptr (SP)  │    │
│  │ B:0x00     │   │      = 0xFFFE   │    │
│  │ C:0x13     │   └─────────────────┘    │
│  │ D:0x00     │                          │
│  │ E:0xD8     │   ┌─────────────────┐    │
│  │ H:0x01     │   │     Flags (F)   │    │
│  │ L:0x4D     │   ├─────────────────┤    │
│  │ AF=0xFFE0  │   │ Z (Zero)        │    │
│  │ BC=0x0013  │   │ N (Subtract)    │    │
│  │ DE=0x00D8  │   │ H (HalfCarry)   │    │
│  │ HL=0x014D  │   │ C (Carry)       │    │
│  └────────────┘   └─────────────────┘    │
│                                          │
│  Execution Model: Fetch → Decode →       │
│                  Execute → Write Back    │
│                                          │
│  Instruction Set: ~240 opcodes           │
│                                          │
└──────────────────────────────────────────┘
```

#### 2. Memory Management Unit (MMU)

```
┌─────────────────────────────────────┐
│     Game Boy Address Space          │
├─────────────────────────────────────┤
│                                     │
│  0x0000 - 0x00FF  │ Boot ROM        │ 256 B
│  0x0100 - 0x3FFF  │ ROM Bank 0      │ 16 KB (always)
│  0x4000 - 0x7FFF  │ ROM Bank N      │ 16 KB (switchable)
│  ────────────────────────────────── │
│  0x8000 - 0x8FFF  │ Tile Data (1)   │ 4 KB
│  0x9000 - 0x9FFF  │ Tile Data (2)   │ 4 KB (VRAM)
│  ────────────────────────────────── │
│  0xA000 - 0xBFFF  │ Cartridge RAM   │ 8 KB
│  ────────────────────────────────── │
│  0xC000 - 0xCFFF  │ WRAM Bank 0     │ 4 KB
│  0xD000 - 0xDFFF  │ WRAM Bank 1     │ 4 KB (Color GB)
│  ────────────────────────────────── │
│  0xE000 - 0xFDFF  │ Echo RAM        │ 7.5 KB
│  0xFE00 - 0xFEFF  │ OAM (Sprites)   │ 160 B
│  0xFF00 - 0xFF7F  │ I/O Registers   │ 128 B
│  0xFF80 - 0xFFFE  │ HRAM            │ 127 B
│  0xFFFF           │ Interrupt Flags │ 1 B
│                                     │
└─────────────────────────────────────┘
```

Key I/O Registers:
- `0xFF40` (LCDC): LCD Control
- `0xFF00` (JOYPAD): Input state
- `0xFF04-0xFF07`: Timers (DIV, TIMA, TMA, TAC)
- `0xFF0F` (IF): Interrupt Flags
- `0xFFFF` (IE): Interrupt Enable

#### 3. Picture Processing Unit (PPU)

```
┌─────────────────────────────────────┐
│      PPU (Pixel Processing)         │
├─────────────────────────────────────┤
│                                     │
│  Screen Resolution: 160 × 144 px    │
│  Tile Size: 8 × 8 px                │
│  Tilemap: 32 × 18 tiles             │
│                                     │
│  ┌──────────────────────────────┐   │
│  │  Tile Data Table (VRAM)      │   │
│  │  0x8000-0x8FFF (128 tiles)   │   │
│  │  0x8800-0x97FF (128 tiles)   │   │
│  └──────────────────────────────┘   │
│            ▲                        │
│            │                        │
│  ┌─────────┴──────────────────────┐ │
│  │  Background/Window Tilemaps    │ │
│  │  0x9800-0x9BFF (BG Map 0)      │ │
│  │  0x9C00-0x9FFF (BG Map 1)      │ │
│  └─────────┬──────────────────────┘ │
│            │                        │
│            ▼                        │
│  ┌──────────────────────────────┐   │
│  │    Scanline Renderer         │   │
│  │  - Fetch tile data           │   │
│  │  - Apply palette             │   │
│  │  - Composite layers          │   │
│  │  - Output pixel data         │   │
│  └──────────────────────────────┘   │
│            │                        │
│            ▼                        │
│  ┌──────────────────────────────┐   │
│  │   Gosu Window Output         │   │
│  │   (160×144 @ 2x scale)       │   │
│  └──────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

#### 4. Execution Flow

```
Main Thread (Gosu)
│
├─► Render Loop (60 FPS)
│   ├─► Handle input (button_down/button_up)
│   ├─► Draw frame from PPU (rect_rle mode)
│   └─► Display FPS overlay
│
└─ Spawn Emulation Thread
    │
    └─► Main Emulation Loop
        │
        ├─► Fetch instruction from ROM[PC]
        ├─► Decode instruction → MicroOp
        ├─► Execute MicroOp steps
        │   ├─► Read operands from memory
        │   ├─► ALU operations
        │   └─► Write results back
        │
        ├─► Accumulate CPU cycles
        │
        ├─► Tick PPU with cycle count
        │   └─► When 70224 cycles: render frame
        │
        ├─► Update Timers (DIV, TIMA)
        │
        ├─► Handle Interrupts (if enabled)
        │   ├─► Check IF register
        │   ├─► Push PC to stack
        │   └─► Jump to interrupt handler
        │
        └─► Repeat until ROM finishes or user quits
```

## Development

### Running Tests

```bash
bundle exec rspec
```

Test coverage includes:
- CPU instruction execution
- Memory access patterns
- PPU scanline rendering
- Input state handling
- Timer behavior

### Key Design Decisions

1. **Micro-Operations**: Complex CPU instructions are decomposed into small, composable steps (fetch operand, ALU op, write result): Work In Progress.

2. **Thread Synchronization**: Emulation runs on a separate thread from Gosu's render thread, synchronized via `Thread::Queue` to prevent race conditions.

3. **Cycle Accuracy**: All components track cycle counts to maintain proper timing for:
   - PPU scanline timing (responsible for VBlank interrupt)
   - Timer counters (DIV, TIMA)
   - Instruction timing

## Performance Notes

- **Target**: ~4.19 MHz CPU (Game Boy clock)
- **Frame Rate**: 59.73 Hz (60 FPS nominal)
- **Rendering**: Scanline-based, 154 scanlines per frame

## References

- [Pan Docs](https://gbdev.io/pandocs/) - Game Boy technical reference
- [CPU Opcode List](https://izik1.github.io/gbops/)
- [Game Boy Hardware Manual](https://en.wikipedia.org/wiki/Game_Boy)

## License

This project is licensed under the MIT License - see the details below:

```
MIT License

Copyright (c) 2026 ABK (https://gitlab.com/abk)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Contributing

Contributions are welcome! Feel free to:
- Open issues for bugs or feature requests
- Submit pull requests with improvements
- Share ideas for optimization or compatibility enhancements

Please ensure tests pass before submitting PRs:
```bash
bundle exec rspec
```

