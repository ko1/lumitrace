---
---

# Lumitrace Spec

## Overview

Lumitrace instruments Ruby source code at load time (via `RubyVM::InstructionSequence.translate` when available), records expression results, and renders text or HTML output that overlays recorded values on your code. It is designed for local “what happened here?” inspection.

## Goals

- Record expression results with minimal friction.
- Limit recorded data size (keep only the last N values per expression).
- Show recorded values inline on a per-file HTML view.
- Support require-time instrumentation for multiple files.

## Non-Goals

- Production-safe tracing.
- Perfect semantic preservation for all Ruby edge cases.

## Public API

### `require "lumitrace"`

- Arguments: none.
- Returns: nothing.
- Side effects: loads core code only (no instrumentation, no `at_exit`).

### `Lumitrace.enable!(max_values: nil, ranges_by_file: nil, root: nil, text: nil, html: nil, json: nil, verbose: nil, at_exit: true)`

- Arguments:
  - `max_values`: integer, string, or nil.
  - `ranges_by_file`: hash or nil. `{ "/path/to/file.rb" => [1..5, 10..12] }`.
  - `text`: boolean or string or nil. When nil, determined from environment variables. When string, uses it as the text output path.
  - `html`: boolean or string or nil. When nil, determined from environment variables.
  - `json`: boolean or string or nil. When nil, determined from environment variables.
  - `verbose`: boolean or nil. When nil, determined from `LUMITRACE_VERBOSE`.
  - `at_exit`: boolean. When true, registers output at exit.
- Returns: `nil`.
- Side effects:
  - Enables require-time instrumentation.
  - Registers a single `at_exit` hook (if `at_exit: true`).
  - Fixes the HTML output directory to the `Dir.pwd` at call time.
- Root scope for instrumentation uses `root` if provided, otherwise `ENV["LUMITRACE_ROOT"]` if set, otherwise `Dir.pwd`.
- Environment variables (resolved by `Lumitrace.enable!`):
  - `LUMITRACE_VALUES_MAX`: default max values per expression when `max_values` is nil (default 3 if unset).
  - `LUMITRACE_ROOT`: root directory used to decide which files are instrumented.
  - `LUMITRACE_HTML`: enable HTML output; `1` uses the default path, otherwise treats the value as the HTML output path. `0`/`false` disables.
  - `LUMITRACE_TEXT`: control text output. `1` forces text on, `0`/`false` disables. If unset, text is enabled only when both HTML and JSON are disabled. Any other value is treated as the text output path.
  - `LUMITRACE_JSON`: enable JSON output; `1` uses the default path, otherwise treats the value as the JSON output path. `0`/`false` disables.
  - `LUMITRACE_GIT_DIFF_UNTRACKED`: include untracked files in git diff ranges (`1` default). Set to `0` to exclude.
  - `LUMITRACE_VERBOSE`: when `1`/`true`, prints verbose logs to stderr.
  - `LUMITRACE_DISABLE`: when `1`/`true`, disables Lumitrace entirely (no instrumentation or output).

### `Lumitrace.disable!`

- Arguments: none.
- Returns: `nil`.
- Side effects: disables instrumentation (does not clear recorded events).


### `require "lumitrace/enable"`

- Arguments: none.
- Returns: nothing.
- Side effects: calls `Lumitrace.enable!` with default arguments.

### `require "lumitrace/enable_git_diff"`

- Arguments: none.
- Returns: nothing.
- Side effects:
  - Computes `ranges_by_file` from `git diff` scoped to the current program file.
  - Calls `Lumitrace.enable!` when diff is non-empty.
- Environment variables:
  - `LUMITRACE_GIT_DIFF=working|staged|base:REV|range:SPEC` selects diff source.
  - `LUMITRACE_GIT_DIFF_CONTEXT=N` expands hunks by +/-N lines (default 3; negative treated as 0).
  - `LUMITRACE_GIT_CMD` overrides the git executable (default: `git`).

## Instrumentation

### Activation

- Call `Lumitrace.enable!`.
- Hook `RubyVM::InstructionSequence.translate` to rewrite files at load time.
- Only instrument files under the configured root directory.
- Optional: restrict instrumentation to specific line ranges per file.

### Root Scope

- Root is `Dir.pwd` (or `ENV["LUMITRACE_ROOT"]` if set).
- Files outside root are ignored.

### Exclusions

- Tool files are excluded to avoid self-instrumentation:
  - `record_instrument.rb`
  - `record_require.rb`
  - `generate_resulted_html.rb`

### Rewriting Strategy

- AST is parsed with Prism.
- For each node, if it matches “wrapable” expression classes, injects:
  - `RecordInstrument.expr_record(file, start_line, start_col, end_line, end_col, (expr))`
- Insertions are done by offset to preserve original formatting.

### Range Filtering

- `ranges_by_file` is a hash like `{ "/path/to/file.rb" => [1..5, 10..12] }`.
- When provided, only files listed in the hash are instrumented.
- For a listed file, only expressions whose start line falls within the listed ranges are instrumented.
- If a listed file has `nil` or an empty array for ranges, the entire file is instrumented.
- HTML rendering respects the same ranges and only shows files that produced events.

### Wrap Targets

- `CallNode` (except those with block bodies)
- Variable reads:
  - `LocalVariableReadNode`
  - `ConstantReadNode`
  - `InstanceVariableReadNode`
  - `ClassVariableReadNode`
  - `GlobalVariableReadNode`
- Literal nodes are excluded (e.g. integer, string, true/false, nil, etc.)

## Recording

- Results are stored per expression key:
  - `(file, start_line, start_col, end_line, end_col)`
- Keep only the last N values (`max_values_per_expr`, default 3).
- Track `total` count for how many times the expression executed.
- Values are stored via `inspect` for non-primitive types.
- String values are truncated to 1000 bytes for storage.

### Output JSON

`lumitrace_recorded.json` contains an array of entries:

```json
{
  "file": "/path/to/file.rb",
  "start_line": 10,
  "start_col": 4,
  "end_line": 10,
  "end_col": 20,
  "values": ["..."],
  "total": 123
}
```

## CLI

### `exe/lumitrace`

```
lumitrace FILE [--text [PATH]] [--html [PATH]] [--json [PATH]] [--max N] [--range SPEC] [--git-diff [MODE]] [--git-diff-context N] [--git-cmd PATH] [--git-diff-no-untracked]
```

- Text is rendered by default (from in-memory events; no JSON file is required).
- `--text` writes text output to stdout (default). When a PATH is provided, writes text output to that file.
- `--html` enables HTML output; optionally specify the output path.
- JSON is written only when `--json` is provided.
- `--json` writes JSON output (default: `lumitrace_recorded.json`).
- `--max` sets max values per expression.
- `--range` restricts instrumentation per file (`FILE` or `FILE:1-5,10-12`). Can be repeated.
- `--git-diff` restricts instrumentation to diff hunks (`working` default; `staged|base:REV|range:SPEC`).
- `--git-diff-context` expands hunks by +/-N lines.
- `--git-cmd` overrides the git executable.
- `--git-diff-no-untracked` excludes untracked files (untracked files are included by default).
- `--verbose` prints verbose logs to stderr.
- `LUMITRACE_VALUES_MAX` sets the default max values per expression.

### Text Output (CLI)

- Text output starts with a header line: `=== Lumitrace Results (text) ===`.
- Each file is printed with a header: `### path/to/file.rb`.
- Each line is prefixed with a line number like ` 12| `.
- Skipped ranges are represented by a line containing `...`.
- Only the last value is shown per expression; if an expression ran multiple times, the last value is annotated with the ordinal run (e.g., `#=> 2 (3rd run)`).
- When `--text` is used and `--max` is not provided, `max_values` defaults to `1`.
- When `ranges_by_file` is provided, only files present in the hash are shown in text output.

## HTML Rendering

- `GenerateResultedHtml.render_all` renders all files in one page.
- Each file is shown in its own section.
- Expressions are marked with an inline icon.
- Hovering the icon shows recorded values.
- Only the last 3 values are shown in the tooltip; additional values are summarized as `... (+N more)`.
- Tooltip is scrollable horizontally for long values.

### Copy/Paste Behavior

- Inline icon uses a separate marker span to reduce copy/paste artifacts.
- Lines are rendered as inline spans with explicit `\n` inserted.

## Known Limitations

- Requires `RubyVM::InstructionSequence.translate` support in the Ruby build.
- Instrumentation is for debugging; semantics may change for unusual edge cases.
- Tool does not attempt to preserve file encoding comments.
