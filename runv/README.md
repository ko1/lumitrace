# runv

A single-file HTML app that runs Ruby.wasm in the browser and shows both the program output and a [Lumitrace](https://github.com/ko1/lumitrace/) -style annotated source view side by side.

[Visit viewer](https://ko1.github.io/runv/)

## Goals
- Run Ruby code in the browser and see STDOUT/STDERR immediately
- Display evaluated values inline on top of the source code
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
2. Wrap selected expressions with `Lumitrace::RecordInstrument.expr_record`
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
