# Lumitrace GitHub Action

Trace a pull request's changed lines while your tests run, and post the recorded
values back as a GitHub **Check Run** — a coverage summary plus a note on any
changed line that never executed. No server and no GitHub App required.

It's two small composite actions you bracket your existing test step with:

- **`ko1/lumitrace/action/setup`** — turns tracing on for the steps that follow.
- **`ko1/lumitrace/action/report`** — builds the check from the trace and posts it.

Your test command is **not** changed: `setup` injects `RUBYOPT=-rlumitrace` and
`LUMITRACE_*` into `$GITHUB_ENV`, so whatever Ruby runs next is traced.

## Quick start

Add the two `uses:` steps around your test step:

```yaml
name: test
on: pull_request

permissions:
  checks: write     # required to post the check run
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - uses: ko1/lumitrace/action/setup@v1

      - run: bundle exec rake test          # your existing test command, unchanged

      - uses: ko1/lumitrace/action/report@v1
        if: always()                        # report even when tests fail
```

That's the whole integration: two steps plus a `permissions:` block.

## What you get

- A `lumitrace` check on the PR with conclusion **neutral** — it never blocks CI.
- A **summary** (Checks tab): per-file coverage of the changed range, plus a few
  recorded-value highlights.
- **Inline annotations** only on changed lines that were **never executed**
  (`total = 0`). Recorded values are *not* annotated on every line — they go to
  the summary (and, if you wire up a backend, a full HTML report).

## Inputs

### `setup`

| input | default | description |
|---|---|---|
| `collect-mode` | `types` | `last` \| `types` \| `history`. `types` keeps raw values out of the public PR view; use `last` to show values. |
| `output` | `lumitrace.json` | Path for the JSON trace output (must match `report`'s `output`). |
| `diff` | _(auto)_ | `LUMITRACE_GIT_DIFF` value (`working` \| `staged` \| `base:REV` \| `range:SPEC`). Empty = PR base, else push `before`, else `working`. |

### `report`

| input | default | description |
|---|---|---|
| `output` | `lumitrace.json` | JSON path (must match `setup`'s `output`). |
| `name` | `lumitrace` | Check run name shown on the PR. |
| `endpoint` | _(empty)_ | Backend base URL to upload the JSON to. Empty = skip upload (no server needed). |
| `audience` | `lumitrace-ci` | OIDC audience for the upload (only used when `endpoint` is set). |

## Notes

- **No `gem install`.** `setup` uses the lumitrace source shipped with the action
  checkout, pinned to the same ref as `@v1`.
- **No `fetch-depth: 0`.** The diff against the PR base is a tree-to-tree compare;
  `setup` fetches just the base commit when it's missing, so the default shallow
  checkout works. (If you set `persist-credentials: false`, add `fetch-depth: 0`.)
- **Fail-safe.** If lumitrace can't load on the runner's Ruby, `setup` warns and
  skips injection — your test step runs exactly as it would without this action.
- **No backend or App needed.** `report` posts the check with the workflow
  `GITHUB_TOKEN`. Set `endpoint` (and `permissions: id-token: write`) only when you
  add a backend for the full HTML report.
- **Fork PRs.** `GITHUB_TOKEN` is read-only on PRs from forks, so the check can't
  be posted there until a GitHub App is added.

## Requirements

- Ruby **3.4+** on the runner (lumitrace needs Prism's `it` node).
- `permissions: checks: write` (and `id-token: write` if uploading to a backend).
