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
