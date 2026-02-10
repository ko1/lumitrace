# runv

A single-file HTML app that runs Ruby.wasm in the browser and shows traced values inline alongside program output, using [Lumitrace](https://github.com/ko1/lumitrace/) -style annotation.

[Visit viewer](https://ko1.github.io/lumitrace/runv/)

## Goals
- Run Ruby code in the browser and see traced values inline
- Keep STDOUT/STDERR visible alongside the inline results
- Keep everything in a single `index.html`

## Layout
- Left: Editor (Ruby input) + Output
- Right: Annotated (inline results)

## Features
- **Ruby.wasm execution**
  - Run via `Run` button or `Ctrl/Cmd + Enter`
- **Output capture**
  - Captures `$stdout` / `$stderr` and renders them in the Output pane
- **Annotated view**
  - Instruments code and records expression values at runtime
  - Generates HTML and renders it via `iframe.srcdoc`
- **Syntax highlighting**
  - Editor highlighting via highlight.js

## How It Works (High Level)
1. Parse the source with Prism
2. Wrap selected expressions with `Lumitrace::R` and assign expression ids
3. `eval` the instrumented code
4. Build HTML from recorded events
5. Render the annotated HTML in the right pane

## Constraints / Notes
- Opening `index.html` via `file://` will fail due to CORS; use a local server
- No file I/O in the browser; everything runs in-memory
- A minimal subset of [Lumitrace](https://github.com/ko1/lumitrace/) is inlined into `index.html`

## Usage
```bash
python3 -m http.server
```

Open `http://localhost:8000/index.html` in your browser.

## Possible Next Steps
- Adjust the Annotated view styling
- Add layout ratios between Editor and Output
- Move inline [Lumitrace](https://github.com/ko1/lumitrace/) code into separate files

---

Built with Ruby.wasm, Prism, and inline [Lumitrace](https://github.com/ko1/lumitrace/) logic.
