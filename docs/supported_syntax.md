---
---

# Supported Syntax

Lumitrace instruments Ruby source by wrapping selected expression nodes with
`Lumitrace::RecordInstrument.expr_record(...)`. It does **not** rewrite the
entire AST, so coverage is best described as "expressions that are safe to wrap
in parentheses and call-position contexts."

This document lists what is supported today, and what is intentionally skipped
to avoid breaking valid Ruby syntax.

## Supported (Instrumented)

The following node kinds are instrumented when they appear in normal expression
positions:

- Method calls (`Prism::CallNode`)
  - Example:
    ```ruby
    foo(bar)
    ```
- Local variable reads (`Prism::LocalVariableReadNode`)
  - Example:
    ```ruby
    x
    ```
- Numbered block parameter reads (`Prism::ItLocalVariableReadNode`)
  - Example:
    ```ruby
    it
    ```
- Constant reads (`Prism::ConstantReadNode`)
  - Example:
    ```ruby
    SomeConst
    ```
- Instance variable reads (`Prism::InstanceVariableReadNode`)
  - Example:
    ```ruby
    @value
    ```
- Class variable reads (`Prism::ClassVariableReadNode`)
  - Example:
    ```ruby
    @@count
    ```
- Global variable reads (`Prism::GlobalVariableReadNode`)
  - Example:
    ```ruby
    $stdout
    ```

Notes:
- Nodes that are not expression reads/calls are generally left as-is (e.g.,
  definitions, control flow, assignment statements, etc.).

## Not Supported (Skipped)

These are intentionally skipped to keep output valid Ruby:

- Definitions and structural nodes (the entire node is never wrapped):
  - `def`, `class`, `module`, `if`, `case`, `while`, `begin`, `rescue`, etc.
  - Example:
    ```ruby
    def foo
      bar
    end
    ```

- Literals (not wrapped):
  - `1`, `"str"`, `:sym`, `true`, `false`, `nil`

- Method calls that have a block with body (`do ... end` / `{ ... }`) are
  instrumented at the call expression level. Example:
  ```ruby
  items.each do |x|
    x + 1
  end
  ```

- Alias statements (both aliasing globals and methods):
  - `alias $ERROR_INFO $!`
  - `alias old_name new_name`

- The receiver part of a singleton method definition:
  - Example:
    ```ruby
    def Foo.bar
      1
    end
    ```
  - `Foo` is **not** instrumented here.

- Embedded variable nodes inside interpolated strings:
  - Example:
    ```ruby
    "#@path?#@query"
    ```
  - `@path` and `@query` inside the interpolation are **not** instrumented.

- Implicit keyword argument values (`token:` style):
  - Example:
    ```ruby
    ec2_metadata_request(EC2_IAM_INFO, token:)
    ```
  - The implicit `token` read is **not** instrumented.

## Rationale

All skips above correspond to syntactic positions where wrapping the token with
`expr_record(...)` would change the Ruby grammar (e.g., alias operands, method
name positions, or implicit keyword arguments).

If you want additional coverage, we can add more targeted rewrites, but they
must preserve valid syntax in those special contexts.
