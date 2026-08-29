# Architecture

Technical notes on how Gemboy is put together. For installing and running it, see the
[README](README.md).

## Overview

`Engine` (`lib/engine.rb`) owns every component and drives the loop: `cpu.step` executes one
instruction and returns the number of T-cycles it took, which is then handed to `ppu.tick` and
`apu.tick`. Everything else follows from that single number.

```
┌───────────────────────────────────────────────────────────────────────┐
│                              Engine                                   │
│                                                                       │
│   Emulation thread                                 Main thread (SDL)  │
│   ┌──────────────┐                                 ┌────────────────┐ │
│   │  CPU (SM83)  │  cycles                         │     Screen     │ │
│   │              ├──────────┐                      │  window, input │ │
│   └──────┬───────┘          │                      │   stats overlay│ │
│          │ read/write       ▼                      └───────▲────────┘ │
│          │           ┌─────────────┐  frame                │          │
│          │           │     PPU     ├────────► render_queue ┘          │
│          │           └──────┬──────┘                                  │
│          ▼                  │ VRAM/OAM                                │
│   ┌─────────────────────────┴───────────────────┐                     │
│   │                    MMU                      │                     │
│   │  WRAM · VRAM · OAM · I/O · HRAM · joypad    │                     │
│   └──────┬──────────────────────────────┬───────┘                     │
│          │ 0x0000-0x7FFF, 0xA000-0xBFFF │ audio registers             │
│          ▼                              ▼                             │
│   ┌─────────────┐                ┌─────────────┐  samples             │
│   │     MBC     │                │     APU     ├────────► audio_queue │
│   │ ROM/RAM     │                │  4 channels │              │       │
│   │ banking,    │                └─────────────┘              ▼       │
│   │ .sav        │                                    ┌────────────────┐│
│   └─────────────┘                                    │  AudioSampler  ││
│                                                      │  (audio thread)││
│                                                      └────────────────┘│
└───────────────────────────────────────────────────────────────────────┘
```

Three threads, communicating only through `Thread::Queue`:

| Thread | Role |
|---|---|
| Main | SDL event loop and drawing. SDL requires the window to live on the main thread, so `Engine#start` ends with `screen.show`, which never returns. |
| Emulation | CPU/PPU/APU stepping, pushes finished frames on `render_queue`. |
| Audio | `AudioSampler` drains `audio_queue` and feeds the SDL audio device. |

## Components

### CPU — `lib/cpu.rb`

Sharp **SM83**, often described as a Z80 relative: it shares part of the instruction encoding
but has no IX/IY registers, no alternate register set, and different flag semantics.

- 8-bit registers `A F B C D E H L`, paired as `AF BC DE HL`, plus `PC` and `SP`.
- Flags: `Z` (zero), `N` (subtract), `H` (half-carry), `C` (carry) in the high nibble of `F`.
- Dispatch through `OPCODE_DISPATCH`, a 256-entry table of method symbols resolved once at
  construction.
- `HALT`, `STOP` and interrupt dispatch are handled in `process_interrupts`.

There is no boot ROM: execution starts directly at `0x0100` with the register state the DMG
boot ROM would have left behind (`lib/boot_values.rb`).

### MMU — `lib/mmu.rb`

Maps the address space and owns everything that is not the cartridge.

| Range | Contents |
|---|---|
| `0x0000-0x3FFF` | ROM bank 0 (fixed, but see MBC1 advanced banking) |
| `0x4000-0x7FFF` | Switchable ROM bank |
| `0x8000-0x9FFF` | VRAM — tile data and tile maps |
| `0xA000-0xBFFF` | Cartridge RAM, when the cartridge has any |
| `0xC000-0xDFFF` | WRAM |
| `0xE000-0xFDFF` | Echo RAM (unmapped here) |
| `0xFE00-0xFE9F` | OAM, 40 sprite entries |
| `0xFF00-0xFF7F` | I/O registers |
| `0xFF80-0xFFFE` | HRAM |
| `0xFFFF` | `IE`, interrupt enable |

Reads and writes are routed by the high byte through a precomputed lookup table rather than a
chain of range comparisons. VRAM and OAM accessibility follows the PPU mode, which is why
`MMU#set_accessible_memory` exists.

Two entry points, deliberately different: `MMU.from_cartridge` builds the machine as it would
be after the boot ROM (I/O registers seeded from `lib/boot_values.rb`), while `MMU.new` leaves
a neutral state and is what the specs use.

### MBC — `lib/mbc/`

`MBC.build` picks an implementation from the cartridge header:

| Type | Class | Notes |
|---|---|---|
| ROM only | `NullMBC` | External RAM enabled from the start when present, since no enable sequence exists |
| MBC1 | `MBC1` | 5-bit bank register, 2-bit secondary register, simple/advanced banking modes, bank-0 quirk |
| MBC3 | `MBC3` | 7-bit bank register plus a real time clock (latching, day counter, halt flag) |
| MBC5 | `MBC5` | 9-bit bank register split across two ranges, no bank-0 quirk |

Anything else raises `RomLoader::UnsupportedCartridgeType` at load time rather than failing
obscurely later. Battery-backed cartridges persist their RAM to a `.sav` next to the ROM
(`lib/mbc/external_ram.rb`).

### PPU — `lib/ppu.rb`

Scanline-based renderer driven by the same cycle count as the CPU.

- 160×144 pixels, 4 shades. 154 scanlines per frame (144 visible plus 10 of VBlank),
  456 T-cycles per scanline, 70224 per frame.
- Mode cycle per visible line: mode 2 (OAM scan, 80 cycles) → mode 3 (pixel transfer, 172) →
  mode 0 (HBlank, 204), then mode 1 (VBlank) for lines 144-153.
- Pixels are produced one dot at a time during mode 3; tile and sprite lookups are cached per
  column and invalidated by a VRAM version counter.
- `LY`/`LYC` comparison is edge-triggered, not level-triggered — a handler rewriting `LYC`
  before its `RETI` would otherwise re-arm the same interrupt.
- `LCDC` can be memoised for a whole tick, `STAT` cannot: the PPU rewrites `STAT` mid-tick, so
  a cached copy is already stale when the interrupt checks read it back.
- With `LCDC` bit 7 cleared the PPU is frozen: `LY` forced to 0, no interrupts, VRAM and OAM
  freely accessible. Games rely on this while bulk-loading VRAM.

### APU — `lib/apu.rb`, `lib/apu/`

Four channels — two pulse (the first with frequency sweep), one wave, one noise (LFSR) —
mixed to stereo. The frame sequencer is clocked by bit 12 of `DIV`, not by the APU itself, so
turning the APU off and on does not restart it from a clean slate. `NR51` routes each channel
to left/right, `NR50` applies the master volume, and a per-side high-pass filter mimics the
DMG capacitor.

### Screen — `lib/screen.rb`

SDL2 through `sdl2-bindings` (Fiddle, no compiled extension). The window is the 160×144
framebuffer at 2× scale plus a 30px border used for two text overlays (emulation speed / FPS,
audio buffer depth). `SDL_RenderPresent` is bound as a blocking function so it releases the
GVL while waiting for vsync.

## Key design decisions

**Cycles as the single source of truth.** No component owns a clock; they all consume the
T-cycles returned by `cpu.step`. Timing bugs therefore show up as wrong cycle counts in one
place rather than as drift between independent clocks.

**Threads split by blocking behaviour.** SDL's event loop and audio device both block; the
emulation must not. Queues are the only shared state, and the emulation thread yields once per
frame (`Thread.pass`) so a CPU-heavy ROM cannot starve the display.

## Performance

Ruby is not the obvious choice for an emulator, so a few things matter:

- YJIT is enabled programmatically at startup (`lib/emugb.rb`); it is worth roughly a factor
  of two here.
- Hot paths avoid allocation: preallocated arrays and structs, palettes and tile columns
  cached, sentinel values chosen so types stay monomorphic for YJIT.
- `PPU#tick` has a fast path for ticks that cannot cross a mode boundary.
- Target is 4.194304 MHz (about 59.7 frames per second); `SpeedLimiter` throttles the
  emulation thread and the current ratio is shown in the top overlay.

Profiling:

```bash
ruby profiling/run_profiling.rb <stackprof|vernier>   # warmed-up loop under a profiler
ruby profiling/read_profiling.rb <stackprof|vernier>  # top 25 self-time offenders
```
