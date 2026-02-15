---
---

# Lumitrace Spec

## Overview

Lumitrace instruments Ruby source code at load time (via `RubyVM::InstructionSequence.translate` when available), records expression results, and renders text or HTML output that overlays recorded values on your code. It is designed for local “what happened here?” inspection.

## AI-Oriented Docs

- AI help reference: `docs/ai-help.md`
- AI schema reference: `docs/ai-schema.md`
- Regenerate both files with: `rake docs:ai`

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

### Library entry points (common usage)

- `require "lumitrace"` + `Lumitrace.enable!(...)`
- `require "lumitrace/enable"` (calls `Lumitrace.enable!`)
- `require "lumitrace/enable_git_diff"` (diff-scoped `Lumitrace.enable!`)
- `LUMITRACE_ENABLE=1` + `require "lumitrace"` (auto-`enable!`)
- `LUMITRACE_ENABLE="-t -h -j ..."` + `require "lumitrace"` (CLI-style options parsed and passed to `enable!`)

### `Lumitrace.enable!(max_samples: nil, ranges_by_file: nil, root: nil, text: nil, html: nil, json: nil, verbose: nil, at_exit: true)`

- Arguments:
  - `max_samples`: integer, string, or nil.
  - `ranges_by_file`: hash or nil. `{ "/path/to/file.rb" => [1..5, 10..12] }`.
  - `text`: boolean or string or nil. When nil, determined from environment variables. When string, uses it as the text output path.
  - `html`: boolean or string or nil. When nil, determined from environment variables.
  - `json`: boolean or string or nil. When nil, determined from environment variables.
  - `verbose`: integer (level) or nil. When nil, determined from `LUMITRACE_VERBOSE`.
  - `at_exit`: boolean. When true, registers output at exit.
- Returns: `nil`.
- Side effects:
  - Enables require-time instrumentation.
  - Registers a single `at_exit` hook (if `at_exit: true`).
  - Fixes the HTML output directory to the `Dir.pwd` at call time.
- Root scope for instrumentation uses `root` if provided, otherwise `ENV["LUMITRACE_ROOT"]` if set, otherwise `Dir.pwd`.
- Environment variables (resolved by `Lumitrace.enable!`):
  - `LUMITRACE_MAX_SAMPLES`: default max samples per expression when `max_samples` is nil (default 3 if unset).
  - `LUMITRACE_COLLECT_MODE`: value collection mode (`last`, `types`, `history`; default `last`).
  - `LUMITRACE_ROOT`: root directory used to decide which files are instrumented.
  - `LUMITRACE_HTML`: enable HTML output; `1` uses the default path, otherwise treats the value as the HTML output path. `0`/`false` disables.
  - `LUMITRACE_TEXT`: control text output. `1` forces text on, `0`/`false` disables. If unset, text is enabled only when both HTML and JSON are disabled. Any other value is treated as the text output path.
  - `LUMITRACE_JSON`: enable JSON output; `1` uses the default path, otherwise treats the value as the JSON output path. `0`/`false` disables.
  - `LUMITRACE_GIT_DIFF_UNTRACKED`: include untracked files in git diff ranges (`1` default). Set to `0` to exclude.
  - `LUMITRACE_VERBOSE`: verbosity level (1-3). `1`/`true` enables basic logs, `2` adds instrumented file names, `3` adds instrumented source output.
  - `LUMITRACE_ENABLE`: when `1`/`true`, `require "lumitrace"` will call `Lumitrace.enable!`. When set to a non-boolean string, it is parsed as CLI-style arguments and passed to `enable!`.
  - `LUMITRACE_RANGE`: semicolon-separated range specs, e.g. `a.rb:1-3,5-6;b.rb`.
  - `LUMITRACE_RESULTS_DIR`: internal use. Shared results directory for fork/exec merge (default: `Dir.tmpdir/lumitrace_results/<user>_<parent_pid>`).
  - `LUMITRACE_RESULTS_PARENT_PID`: internal use. Parent PID for fork/exec merge (auto-set).

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
  - `LUMITRACE_RANGE` can be used to pass explicit ranges via env.

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
  - `Lumitrace::R(id, (expr))` where `id` maps to location metadata.
- Insertions are done by offset to preserve original formatting.

### Range Filtering

- `ranges_by_file` is a hash like `{ "/path/to/file.rb" => [1..5, 10..12] }`.
- When provided, only files listed in the hash are instrumented.
- For a listed file, only expressions whose start line falls within the listed ranges are instrumented.
- If a listed file has `nil` or an empty array for ranges, the entire file is instrumented.
- HTML rendering respects the same ranges and only shows files that produced events.

### Wrap Targets

- `CallNode` (except those with block bodies)
- `YieldNode`
- Variable reads:
  - `LocalVariableReadNode`
  - `ConstantReadNode`
  - `InstanceVariableReadNode`
  - `ClassVariableReadNode`
  - `GlobalVariableReadNode`
- Literal nodes are excluded (e.g. integer, string, true/false, nil, etc.)
- Method and block arguments are recorded by inserting `Lumitrace::R` at the start of the body.

## Recording

- Results are stored per expression key:
  - `id` (an integer assigned at instrumentation time) with a separate `id -> location` table.
- Collection mode is selected by `collect_mode` (`last`, `types`, `history`; default `last`).
- In `history` mode, keep only the last N values (`max_samples_per_expr`, default 3).
- Track `total` count for how many times the expression executed.
- In `collect_mode=last`, `last_value.preview` is always the `inspect` result string.
- `last_value.length` is included only when `preview` is truncated.
- Argument records are stored alongside expression records with `kind: "arg"` and `name` (argument name).

## Fork/Exec Merge

- Fork/exec results are merged by default.
- The parent process writes final text/HTML/JSON.
- Child processes write JSON fragments under `LUMITRACE_RESULTS_DIR` and do not write final outputs.
- When `Process._fork` is available, Lumitrace hooks it to reset child events immediately after fork.
- `exec` inherits `LUMITRACE_RESULTS_DIR` and `LUMITRACE_RESULTS_PARENT_PID` via the environment. `Lumitrace.enable!` also appends `-rlumitrace` to `RUBYOPT` to ensure the exec'd process loads Lumitrace.

### Output JSON

`lumitrace_recorded.json` contains an array of entries.

`collect_mode=last` (default):

```json
{
  "file": "/path/to/file.rb",
  "start_line": 10,
  "start_col": 4,
  "end_line": 10,
  "end_col": 20,
  "kind": "expr",
  "name": null,
  "last_value": { "type": "String", "preview": "\"ok\"" },
  "types": { "Integer": 10, "NilClass": 2, "String": 111 },
  "total": 123
}
```

`collect_mode=types`:

```json
{
  "file": "/path/to/file.rb",
  "start_line": 10,
  "start_col": 4,
  "end_line": 10,
  "end_col": 20,
  "kind": "expr",
  "name": null,
  "types": { "Integer": 10, "NilClass": 2, "String": 111 },
  "total": 123
}
```

`collect_mode=history`:

```json
{
  "file": "/path/to/file.rb",
  "start_line": 10,
  "start_col": 4,
  "end_line": 10,
  "end_col": 20,
  "kind": "expr",
  "name": null,
  "sampled_values": [
    { "type": "Integer", "preview": "42" },
    { "type": "NilClass", "preview": "nil" },
    { "type": "String", "preview": "\"ok\"" }
  ],
  "types": { "Integer": 10, "NilClass": 2, "String": 111 },
  "total": 123
}
```

- `last_value`: summary of the last observed value: `{ type, preview }` (+ `length` only when truncated).
- `types`: observed Ruby class counts (class name => count).
- `sampled_values`: retained sample (last N values) of summary objects (`{ type, preview }` + optional `length`) in `history` mode.

## CLI

### `lumitrace`

```
lumitrace [options] script.rb [ruby_opt]
lumitrace [options] exec CMD [args...]
```

- Text is rendered by default (from in-memory events; no JSON file is required).
- `-t` enables text output to stdout. `--text=PATH` writes to a file.
- `-h` enables HTML output (default path). `--html=PATH` writes to a file.
- `-j` enables JSON output (default path). `--json=PATH` writes to a file.
- `-g` enables git diff with `working` mode. `--git-diff=MODE` selects `staged|base:REV|range:SPEC`.
- `--max-samples` sets max samples per expression in `collect_mode=history`.
- `--collect-mode` sets value collection mode (`last|types|history`).
- `--range` restricts instrumentation per file (`FILE` or `FILE:1-5,10-12`). Can be repeated.
- `--git-diff=MODE` restricts instrumentation to diff hunks (`staged|base:REV|range:SPEC`).
- `--git-diff-context` expands hunks by +/-N lines.
- `--git-cmd` overrides the git executable.
- `--git-diff-no-untracked` excludes untracked files (untracked files are included by default).
- `--verbose[=LEVEL]` prints verbose logs to stderr (level 1-3).
- `LUMITRACE_MAX_SAMPLES` sets the default max samples per expression.
- The CLI launches a child process (Ruby or `exec` target) with `RUBYOPT=-rlumitrace` and `LUMITRACE_*` env vars.

### Text Output (CLI)

- Text output starts with a header line: `=== Lumitrace Results (text) ===`.
- Each file is printed with a header: `### path/to/file.rb`.
- Each line is prefixed with a line number like ` 12| `.
- Lines where all instrumentable expressions are unexecuted are prefixed with `!`.
- Skipped ranges are represented by a line containing `...`.
- Only the last value is shown per expression as `value (Type)`; if an expression ran multiple times, the last value is annotated with the ordinal run (e.g., `#=> 2 (Integer) (3rd run)`).
- When `collect_mode=history` and `--text` is used with no `--max-samples`, `max_samples` defaults to `1`.
- When `ranges_by_file` is provided, only files present in the hash are shown in text output.
- When writing to stdout (`tty: true`), long comments are truncated to the terminal width (using `COLUMNS` or `IO.console.winsize`). File output is not truncated.

## HTML Rendering

- `GenerateResultedHtml.render_all` renders all files in one page.
- The page header shows the active collect mode:
  - `Mode: last (last value)`
  - `Mode: types (type counts)`
  - `Mode: history (last N sample[s])`
  - In `history`, `N` uses configured `max_samples` when available; otherwise it is inferred from the loaded events.
- Each file is shown in its own section.
- Expressions are marked with an inline icon (`🔎` for executed, `∅` for not hit).
- Hovering the icon shows recorded values.
- Only the last 3 values are shown in the tooltip as `value (Type)`; additional values are summarized as `... (+N more)`.
- Tooltip is scrollable horizontally for long values.
- When ranges are used, skipped sections are shown as `...` in the line-number column.
- Lines where all instrumentable expressions are unexecuted are highlighted in a light red. If a line mixes executed and unexecuted expressions, only the unexecuted expressions are highlighted.

### Copy/Paste Behavior

- Inline icon uses a separate marker span to reduce copy/paste artifacts.
- Lines are rendered as inline spans with explicit `\n` inserted.

## Known Limitations

- Requires `RubyVM::InstructionSequence.translate` support in the Ruby build.
- Instrumentation is for debugging; semantics may change for unusual edge cases.
- Tool does not attempt to preserve file encoding comments.
