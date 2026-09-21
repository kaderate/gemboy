# Browser build

Gemboy can run in a browser through CRuby's WebAssembly build (`ruby.wasm`). The browser build keeps the emulator core in Ruby and replaces SDL with Canvas, DOM keyboard events, and a JavaScript framebuffer adapter.

The GitHub Actions workflow builds `web/gemboy.wasm` and uploads it as the `gemboy-wasm` artifact. The source `web/index.html` can be served from any static HTTP server after the artifact is extracted.

## Local build

```bash
cd wasm
bundle install
bundle exec rbwasm build --ruby-version 4.0 -o ../web/ruby.wasm
bundle exec rbwasm pack ../web/ruby.wasm --dir ../lib::/lib --dir ../web::/web -o ../web/gemboy.wasm
rm ../web/ruby.wasm
```

Then serve `web/` over HTTP and open `index.html`. A ROM is loaded with the file picker. Controls are Arrow keys, `Z`/`X`, Enter, and Right Shift.

## Performance

The browser build runs well under real Game Boy speed (measured on Tetris: emulating one
70,224-cycle frame against a 16.7ms/frame budget). This is a hard ceiling, not a bug to fix:

| Environment           | Emulate/frame | Speed ratio |
|-----------------------|---------------|-------------|
| Native (YJIT enabled) | ~7.6ms        | ~2.2x       |
| Browser, Chrome       | ~70ms         | ~0.23x      |
| Browser, Firefox      | ~106ms        | ~0.15x      |

- Emulation dominates the frame budget, not the pixel-bridge to Canvas (~6-10ms, and the
  emulate time is unchanged with rendering disabled entirely) — the JS interop is not the
  bottleneck.
- `RubyVM::YJIT.enable` is a no-op here: YJIT generates native machine code at runtime, which
  requires mapping executable memory. A WASI sandbox doesn't allow that, so the interpreter
  falls back to plain bytecode dispatch — the same code path the native SDL build only uses
  when YJIT is disabled. That gap (~14x slower than native) is structural, not something this
  build's code can configure its way out of.
- Chrome is consistently faster than Firefox (~1.5x on the same ROM) — the two engines' wasm
  compilers (V8's Liftoff/TurboFan tiering vs SpiderMonkey's) optimize the compiled interpreter
  loop differently. Still wasm-interpreted Ruby either way, not a native JIT reappearing.

So this build is a proof of concept (Ruby's emulator core running unmodified in a browser), not
a playable-speed emulator. Closing that gap would mean optimizing the CPU/PPU hot path itself,
which would also benefit the native build — a separate, much larger effort than the browser
port.

Append `?norender=1` to the page URL to skip the pixel bridge entirely (used to isolate
emulation cost from JS marshaling cost while measuring the above).
