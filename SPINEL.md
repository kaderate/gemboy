# Spinel port

This repository can be compiled with [Spinel](https://github.com/matz/spinel) for the headless emulator core.

The normal SDL frontend remains a CRuby target for now. The Spinel target deliberately uses `Driver`, which contains no SDL dependency and exercises the cartridge, motherboard, CPU, MMU, PPU and APU core.

## Build

Build Spinel first:

```sh
make deps
make
```

Then, from this repository:

```sh
spinel bin/gemboy-spinel -o gemboy-spinel
./gemboy-spinel path/to/game.gb 60
```

The second argument is the number of Game Boy frames to emulate. A successful run prints the number of frames completed.

## Why headless first?

Gemboy's interactive `Screen` currently depends on the `sdl2-bindings` Ruby extension. Spinel's FFI is compile-time and can link plain C libraries directly, but it does not load CRuby native extensions. The core already has a clean SDL-free `Driver`, so keeping the first Spinel target headless gives us a small, deterministic compilation target while leaving the existing CRuby frontend untouched.

The next step is to replace `sdl2-bindings` in `Screen` and the SDL input manager with Spinel FFI declarations. Spinel FFI supports `ffi_lib`, `ffi_func`, integer constants, opaque pointers and static buffers; it does not currently provide general C structs or callbacks, so SDL structs should initially be handled with `ffi_buffer`/field readers or small C shim functions where necessary.

## Current scope

- CPU/MMU/cartridge/PPU/APU core: included through `Driver`
- `.gb`/`.gbc` cartridge loading: retained
- SDL window/input/audio: not part of the Spinel target yet
- Save-state UI/debug web UI: not part of the Spinel target yet
