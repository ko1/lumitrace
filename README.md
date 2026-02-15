# Lumitrace

Lumitrace instruments Ruby source code at load time, records expression results, and renders an HTML view that overlays recorded values on your code. It is designed for quick, local “what happened here?” inspection during test runs or scripts.

## Useful links

- [runv/](https://ko1.github.io/lumitrace/runv/): Lumitrace demonstration Ruby playground with inlined tracing
- [Tutorial](https://ko1.github.io/lumitrace/docs/tutorial.html)
- [Tutorial in Japanese](https://ko1.github.io/lumitrace/docs/tutorial.ja.html)
- [Spec](https://ko1.github.io/lumitrace/docs/spec.html)
- [AI Help](https://ko1.github.io/lumitrace/docs/ai-help.html)
- [AI Schema](https://ko1.github.io/lumitrace/docs/ai-schema.html)
- [Supported Syntax](https://ko1.github.io/lumitrace/docs/supported_syntax.html)
- [GitHub repository](https://github.com/ko1/lumitrace)


## How It Works

Lumitrace hooks `RubyVM::InstructionSequence.translate` (when available) to rewrite files at require-time. It records expression results and renders an HTML view that shows them inline. Only the last N values per expression are kept to avoid huge output.

## Usage

### CLI

Run a script and emit text output (default):

```bash
lumitrace path/to/entry.rb
```

Run another command via exec:

```bash
lumitrace exec rake test
```

Emit HTML output:

```bash
lumitrace -h path/to/entry.rb
```

Limit the number of recorded values per expression (defaults to 3):

```bash
LUMITRACE_MAX_SAMPLES=5 lumitrace path/to/entry.rb
```

Write JSON output explicitly:

```bash
lumitrace -j path/to/entry.rb
lumitrace --json=out/lumitrace_recorded.json path/to/entry.rb
```

Restrict to specific line ranges:

```bash
lumitrace --range path/to/entry.rb:10-20,30-35 path/to/entry.rb
```

Show AI/human help:

```bash
lumitrace help
lumitrace help --format json
lumitrace schema --format json
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

- Text: printed by default; use `--text=PATH` to write to a file.
- HTML: `lumitrace_recorded.html` by default, or `--html=PATH`.
- JSON: written only when `--json` (CLI) or `LUMITRACE_JSON` (library/CLI) is provided. Default filename is `lumitrace_recorded.json`.
- JSON collection mode: `--collect-mode=last|types|history` (default `last`).
- Fork/exec: merged by default. Child processes write fragments under `LUMITRACE_RESULTS_DIR`.

JSON event entries always include `types` (type-name => count).

```json
{
  "file": "/abs/path/app.rb",
  "start_line": 10,
  "start_col": 2,
  "end_line": 10,
  "end_col": 9,
  "kind": "expr",
  "types": { "Integer": 3, "NilClass": 1 },
  "total": 4
}
```

## Environment Variables

- `LUMITRACE_MAX_SAMPLES`: default max samples per expression (default 3 if unset).
- `LUMITRACE_COLLECT_MODE`: value collection mode (`last`, `types`, `history`; default `last`).
- `LUMITRACE_ROOT`: root directory used to decide which files are instrumented.
- `LUMITRACE_TEXT`: control text output. `1` forces text on, `0`/`false` disables. Any other value is treated as the text output path.
- `LUMITRACE_HTML`: enable HTML output; `1` uses the default path, otherwise treats the value as the HTML output path. `0`/`false` disables.
- `LUMITRACE_JSON`: enable JSON output; `1` uses the default path, otherwise treats the value as the JSON output path. `0`/`false` disables.
- `LUMITRACE_ENABLE`: when `1`/`true`, `require "lumitrace"` will call `Lumitrace.enable!`. When set to a non-boolean string, it is parsed as CLI-style arguments and passed to `enable!`.
- `LUMITRACE_VERBOSE`: verbosity level (1-3). `1`/`true` enables basic logs, `2` adds instrumented file names, `3` adds instrumented source output.
- `LUMITRACE_RANGE`: semicolon-separated range specs (e.g. `a.rb:1-3,5-6;b.rb`).
- `LUMITRACE_RESULTS_DIR`: internal use. Shared results directory for fork/exec merge (default: `Dir.tmpdir/lumitrace_results/<user>_<parent_pid>`).
- `LUMITRACE_RESULTS_PARENT_PID`: internal use. Parent PID for fork/exec merge (auto-set).
- `LUMITRACE_GIT_DIFF=working|staged|base:REV|range:SPEC`: diff source for `enable_git_diff`.
- `LUMITRACE_GIT_DIFF_CONTEXT=N`: expand diff hunks by +/-N lines (default 3).
- `LUMITRACE_GIT_CMD`: git executable override (default `git`).
- `LUMITRACE_GIT_DIFF_UNTRACKED`: include untracked files in git diff ranges (`1` default). Set to `0` to exclude.

## Notes And Limitations

- Requires `RubyVM::InstructionSequence.translate` support.
- Very large projects or hot loops can still generate large HTML; use `LUMITRACE_MAX_SAMPLES`.
- Instrumentation changes evaluation order for debugging, not for production.

## Development

Install dependencies:

```bash
bundle install
```

Run the CLI locally:

```bash
lumitrace path/to/entry.rb
```
