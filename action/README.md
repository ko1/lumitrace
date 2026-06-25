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
  checks: write     # post the check run
  contents: read
  id-token: write   # upload the report to lumitrace.atdot.net for a linked HTML report

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

That's the whole integration: two steps plus a `permissions:` block. Drop
`id-token: write` and you still get the PR check — just without the linked
hosted report (nothing is uploaded anywhere).

## Where results appear

One CI run, three places — each more detailed than the last:

```
 PR push
   │  setup turns tracing on, your tests run, report collects the result
   ▼
 ┌─────────────────────────────────────────────────────────────────────┐
 │ ① Files changed   ⚠ annotation only on changed lines never covered   │  checks: write
 │ ② Checks tab      summary: coverage table, value highlights, links   │  checks: write
 │ ③ Hosted report   full HTML, recorded values overlaid on every line  │  id-token: write
 └─────────────────────────────────────────────────────────────────────┘
     ① + ② are the PR check itself.   ② links to ③ (details_url).
```

| | Surface | Shows | Needs |
|---|---|---|---|
| ① | PR **Files changed** | Inline annotation **only on uncovered** changed lines (`total = 0`) — values are *not* put on every line, to keep the diff readable | `checks: write` |
| ② | PR **Checks tab** | Title (`N uncovered · M traced`), per-file coverage table, a few value highlights, and links to ③ and the raw JSON | `checks: write` |
| ③ | **lumitrace.atdot.net/r/…** | The full report: every traced line annotated with its recorded value/type | `id-token: write` |

The check is **neutral** — it never blocks CI. Only ③ needs `id-token: write`;
without it you still get ① + ②.

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
| `html` | `lumitrace.html` | HTML path (must match `setup`'s `html`); uploaded with the JSON. |
| `endpoint` | `https://lumitrace.atdot.net` | Backend the report is uploaded to. Upload only happens when the workflow grants `id-token: write`; set to `""` to disable, or point at your own server. |
| `audience` | `lumitrace-ci` | OIDC audience for the upload. |

## Notes

- **No `gem install`.** `setup` uses the lumitrace source shipped with the action
  checkout, pinned to the same ref as `@v1`.
- **No `fetch-depth: 0`.** The diff against the PR base is a tree-to-tree compare;
  `setup` fetches just the base commit when it's missing, so the default shallow
  checkout works. (If you set `persist-credentials: false`, add `fetch-depth: 0`.)
- **Fail-safe.** If lumitrace can't load on the runner's Ruby, `setup` warns and
  skips injection — your test step runs exactly as it would without this action.
- **JSON for tooling / AI.** The check summary links the raw trace JSON
  (`/r/<token>/data`) alongside the HTML report, so you (or your own AI / tooling)
  can pull the data. Its shape is documented by `lumitrace schema --format json`.
- **Hosted report is opt-in via `id-token: write`.** With that permission, `report`
  uploads to `lumitrace.atdot.net` (OIDC-authenticated, no shared secret) and links
  the check to the HTML report. Without it, nothing is uploaded — you just get the
  check, posted with the workflow `GITHUB_TOKEN`. Any upload failure is non-fatal.
- **Fork PRs.** `GITHUB_TOKEN` is read-only on PRs from forks, so the check can't
  be posted there until a GitHub App is added.

## Requirements

- Ruby **3.4+** on the runner (lumitrace needs Prism's `it` node).
- `permissions: checks: write` (and `id-token: write` if uploading to a backend).
