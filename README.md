# Lumitrace

Lumitrace instruments Ruby source code at load time, records expression results, and renders an HTML view that overlays recorded values on your code. It is designed for quick, local “what happened here?” inspection during test runs or scripts.

## How It Works

Lumitrace hooks `RubyVM::InstructionSequence.translate` (when available) to rewrite files at require-time. It records expression results into `record_events.json`, keeping only the last N values per expression to avoid huge output. The HTML renderer aggregates results across files and shows them inline.

## Usage

Run a script and emit HTML:

```bash
ruby exe/lumitrace path/to/entry.rb --html
```

Limit the number of recorded values per expression (defaults to 3):

```bash
LUMITRACE_VALUES_MAX=5 ruby exe/lumitrace path/to/entry.rb --html
```

By default, Lumitrace instruments files under the current working directory. Files outside the root are ignored. You can override the root with `LUMITRACE_ROOT`.

## Output

Running Lumitrace produces:

- `record_events.json` (JSON results, aggregated per expression)
- `recorded.html` (HTML view, if `--html` is passed)

## Notes And Limitations

- Requires `RubyVM::InstructionSequence.translate` support.
- Very large projects or hot loops can still generate large JSON; use `RST_MAX`.
- Instrumentation changes evaluation order for debugging, not for production.

## Development

Install dependencies:

```bash
bundle install
```

Run the CLI locally:

```bash
ruby exe/lumitrace path/to/entry.rb --html
```
