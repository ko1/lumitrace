# Lumitrace

Lumitrace instruments Ruby source code at load time, records expression results, and renders an HTML view that overlays recorded values on your code. It is designed for quick, local “what happened here?” inspection during test runs or scripts.

## Useful links

- [runv/](https://ko1.github.io/lumitrace/runv/): Lumitrace demonstration Ruby playground with inlined tracing
- [Tutorial](https://ko1.github.io/lumitrace/docs/tutorial.html)
- [Tutorial in Japanese](https://ko1.github.io/lumitrace/docs/tutorial.ja.html)
- [Spec](https://ko1.github.io/lumitrace/docs/spec.html)
- [Supported Syntax](https://ko1.github.io/lumitrace/docs/supported_syntax.html)
- [GitHub repository](https://github.com/ko1/lumitrace)


## How It Works

Lumitrace hooks `RubyVM::InstructionSequence.translate` (when available) to rewrite files at require-time. It records expression results and renders an HTML view that shows them inline. Only the last N values per expression are kept to avoid huge output.

## Usage

### CLI

Run a script and emit text output (default):

```bash
ruby exe/lumitrace path/to/entry.rb
```

Emit HTML output:

```bash
ruby exe/lumitrace path/to/entry.rb --html
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

- Text: printed by default; use `--text PATH` to write to a file.
- HTML: `lumitrace_recorded.html` by default, or `--html PATH`.
- JSON: written only when `--json` (CLI) or `LUMITRACE_JSON` (library/CLI) is provided. Default filename is `lumitrace_recorded.json`.

## Environment Variables

- `LUMITRACE_VALUES_MAX`: default max values per expression (default 3 if unset).
- `LUMITRACE_ROOT`: root directory used to decide which files are instrumented.
- `LUMITRACE_TEXT`: control text output. `1` forces text on, `0`/`false` disables. Any other value is treated as the text output path.
- `LUMITRACE_HTML`: enable HTML output; `1` uses the default path, otherwise treats the value as the HTML output path. `0`/`false` disables.
- `LUMITRACE_JSON`: enable JSON output; `1` uses the default path, otherwise treats the value as the JSON output path. `0`/`false` disables.
- `LUMITRACE_ENABLE`: when `1`/`true`, `require "lumitrace"` will call `Lumitrace.enable!`. When set to a non-boolean string, it is parsed as CLI-style arguments and passed to `enable!`.
- `LUMITRACE_VERBOSE`: when `1`/`true`, prints verbose logs to stderr.
- `LUMITRACE_GIT_DIFF=working|staged|base:REV|range:SPEC`: diff source for `enable_git_diff`.
- `LUMITRACE_GIT_DIFF_CONTEXT=N`: expand diff hunks by +/-N lines (default 3).
- `LUMITRACE_GIT_CMD`: git executable override (default `git`).
- `LUMITRACE_GIT_DIFF_UNTRACKED`: include untracked files in git diff ranges (`1` default). Set to `0` to exclude.

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
