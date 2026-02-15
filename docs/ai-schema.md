<!-- generated file: do not edit. run `rake docs:ai` -->

# Lumitrace JSON Schema

- Version: 0.4.0
- Schema version: 1
- Top level: array of event

## Common Event Fields
- `file` (string, required) - Absolute source path.
- `start_line` (integer, required)
- `start_col` (integer, required)
- `end_line` (integer, required)
- `end_col` (integer, required)
- `kind` (string, required)
- `name` (string|null, optional) - Present for kind=arg.
- `total` (integer, required) - Execution count.
- `types` (object, required) - Ruby class name => observed count.

## Value Summary Fields
- `type` (string, required) - Ruby class name.
- `preview` (string, required) - Value preview string (inspect-based).
- `length` (integer, optional) - Original preview length when preview was truncated.

## Collect Modes
- `last`
  - required fields: file, start_line, start_col, end_line, end_col, kind, total, types, last_value
  - optional fields: name
  - `last_value`: value_summary
- `types`
  - required fields: file, start_line, start_col, end_line, end_col, kind, total, types
  - optional fields: name
- `history`
  - required fields: file, start_line, start_col, end_line, end_col, kind, total, types, sampled_values
  - optional fields: name
  - `sampled_values`: array (items: value_summary)
