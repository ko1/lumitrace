# Lumitrace

Lumitrace instruments Ruby source code at load time, records expression results, and renders an HTML view that overlays recorded values on your code. It is designed for quick, local “what happened here?” inspection during test runs or scripts.

## Useful links

- [runv/](runv/): Lumitrace demonstration Ruby playground with inlined tracing
- [Tutorial](doc/tutorial.md)
- [Tutorial in Japanese](doc/tutorial.ja.md)
- [doc/spec.md](doc/spec.md)
- [doc/supported_syntax.md](doc/supported_syntax.md)
- [GitHub repository](https://github.com/ko1/lumitrace)


## How It Works

Lumitrace hooks `RubyVM::InstructionSequence.translate` (when available) to rewrite files at require-time. It records expression results and renders an HTML view that shows them inline. Only the last N values per expression are kept to avoid huge output.

## Usage

### CLI

Run a script and emit HTML (default output: `lumitrace_recorded.html`):

```bash
ruby exe/lumitrace path/to/entry.rb
```

Limit the number of recorded values per expression (defaults to 3):

```bash
LUMITRACE_VALUES_MAX=5 ruby exe/lumitrace path/to/entry.rb
```

Write JSON output explicitly:

```bash
ruby exe/lumitrace path/to/entry.rb --json
ruby exe/lumitrace path/to/entry.rb --json out/lumitrace_recorded.json
```

Restrict to specific line ranges:

```bash
ruby exe/lumitrace path/to/entry.rb --range path/to/entry.rb:10-20,30-35
```

### Library

Enable instrumentation and HTML output at exit:

```ruby
require "lumitrace"
Lumitrace.enable!
```

Enable only for diff ranges (current file):

```ruby
require "lumitrace/enable_git_diff"
```

If you want to enable via a single require:

```ruby
require "lumitrace/enable"
```

## Output

- HTML: `lumitrace_recorded.html` by default, override with `LUMITRACE_HTML_OUT`.
- JSON: written only when `--json` (CLI) or `LUMITRACE_JSON_OUT` (library) is provided. Default filename is `lumitrace_recorded.json`.

## Environment Variables

- `LUMITRACE_VALUES_MAX`: default max values per expression (default 3 if unset).
- `LUMITRACE_ROOT`: root directory used to decide which files are instrumented.
- `LUMITRACE_HTML_OUT`: override HTML output path.
- `LUMITRACE_JSON_OUT`: if set, writes JSON to this path at exit.
- `LUMITRACE_GIT_DIFF=working|staged|base:REV|range:SPEC`: diff source for `enable_git_diff`.
- `LUMITRACE_GIT_DIFF_CONTEXT=N`: expand diff hunks by +/-N lines (default 3).
- `LUMITRACE_GIT_CMD`: git executable override (default `git`).

## Notes And Limitations

- Requires `RubyVM::InstructionSequence.translate` support.
- Very large projects or hot loops can still generate large HTML; use `LUMITRACE_VALUES_MAX`.
- Instrumentation changes evaluation order for debugging, not for production.

## Development

Install dependencies:

```bash
bundle install
```

Run the CLI locally:

```bash
ruby exe/lumitrace path/to/entry.rb
```
