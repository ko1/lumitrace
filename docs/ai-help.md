<!-- generated file: do not edit. run `rake docs:ai` -->

# Lumitrace Help

AI agents: run `lumitrace help --format json` to get structured help.

- Version: 0.6.2
- Help version: 1
- Primary JSON entrypoint: `lumitrace help --format json`
- Schema JSON entrypoint: `lumitrace schema --format json`

## Recommended Flow
- Read `lumitrace help --format json`.
- Read `lumitrace schema --format json` to understand output structure.
- Run lumitrace with `--collect-mode` and optional `--max-samples`.
- Inspect JSON/HTML/text outputs depending on your task.

## AI Usage Tips
- First run with `--collect-mode types` to get a compact shape of runtime behavior.
- Then switch to `--collect-mode last` for final value inspection on suspicious lines.
- Use `--collect-mode history --max-samples N` only when value transitions matter.
- Combine `--range` or `--git-diff` to keep outputs small and focused.
- -j, -h, -t are flags with optional arguments joined by = (e.g. --json=PATH or -jPATH). Do NOT put a space before the path: `-j foo.json` treats foo.json as the script to run, not the output path.

## Commands
- `lumitrace [options] script.rb [ruby_opt]`
  - Run a Ruby script with Lumitrace enabled.
- `lumitrace [options] exec CMD [args...]`
  - Use this for command-style entrypoints (e.g. rails/rspec via binstubs or bundle exec).
- `lumitrace help [--format text|json]`
  - Show AI/human help.
- `lumitrace schema [--format text|json]`
  - Show output schema for each collect mode.

## Collect Modes
- `last`: Keep only the last observed value and type counts.
- `types`: Keep only type counts and total hit count.
- `history`: Keep last N sampled values and type counts.

## Key Options
- `--collect-mode` (default="last"; values=last,types,history)
- `--max-samples` (default=3; Used by history mode.)
- `-j, --json[=PATH]` (Emit JSON output. Flag only: -j uses default path. To specify path: --json=PATH or -jPATH (no space).)
- `-h, --html[=PATH]` (Emit HTML output. Flag only: -h uses default path. To specify path: --html=PATH or -hPATH (no space).)
- `-t, --text[=PATH]` (Emit text output. Flag only: -t uses default path. To specify path: --text=PATH or -tPATH (no space).)
- `-g, --git-diff[=MODE]` (Restrict instrumentation to diff hunks.)
- `--range SPEC` (repeatable=true; Restrict instrumentation to file ranges.)
- `--git-diff-context N` (Expand diff hunks by +/-N lines.)
- `--git-cmd PATH` (Git executable for diff.)
- `--git-diff-no-untracked` (Exclude untracked files from diff.)
- `--root PATH` (Root directory for instrumentation.)
- `--verbose[=LEVEL]` (Verbose logs to stderr (level 1-3).)

## Examples
- `lumitrace --collect-mode history --max-samples 5 -j app.rb`
- `lumitrace --collect-mode types -h -j app.rb`
- `lumitrace --collect-mode last -j exec bin/rails test`
- `lumitrace --json=output.json exec bin/rails test`
- `lumitrace -j --html=report.html app.rb`
- `lumitrace help --format json`
- `lumitrace schema --format json`
