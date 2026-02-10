# AGENTS

This file describes how agents should work in this repository.

## Purpose
- Keep changes focused on Lumitrace and its docs/tests.
- Prefer minimal, reviewable edits over wide refactors.

## Where To Look First
- Overview and usage: `README.md`
- Detailed behavior/spec: `docs/spec.md`
- Syntax coverage: `docs/supported_syntax.md`
- Tutorials: `docs/tutorial.md`, `docs/tutorial.ja.md`

## Repository Layout
- Source code: `lib/`, `exe/`, `bin/`
- Docs: `docs/`
- Tests: `test/`
- Samples: `sample/`

## Coding And Style
- Follow existing Ruby style and structure in nearby files.
- Keep changes small and localized when possible.
- Add comments only when logic is non-obvious.

## Tests
- Prefer running the smallest relevant test set.
- When source code changes, run tests by default (at least `rake test`).
- If you cannot run tests, say so and explain why.

## Safety
- Do not delete or rewrite large sections without a clear reason.
- Do not use destructive git commands unless asked.

## Communication
- Summarize what you changed and why.
- Call out any assumptions or follow-ups needed.
