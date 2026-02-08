# Sample Project Workflow

## Lumitrace with GitHub Actions

Here's the idea we landed on for CI, written as a short story so it is easy to remember.

We wanted the diff-aware text summary to appear right inside the GitHub Actions log. But we also wanted it to be based on the PR base branch, not the developer's local default branch name (so we never rely on `master` or `main` being present). Since we only run on PRs, that led us to a simple rule:

1. Run only on `pull_request`.
2. Fetch full history so the base ref exists.
3. Set `LUMITRACE_GIT_DIFF` only for the Lumitrace step, using the PR base ref.
4. Run the test command as usual.

That way the log includes a compact, diff-scoped view like this:

```
=== Lumitrace Results (text) ===
### test/test_sample_test.rb (lines: 16-25)
16|     assert_equal 420, (30 + 3 * 4) * 10 #=> true
17|   end
18| 
19|   def test_hoge
20|     assert_equal 4200, (30 + 3 * 4) * 100 #=> true
21|   end
22| 
23|   def test_baz
24|     assert_equal 43, 30 + 3 * 4 + 1 #=> true
25|   end
```

Practical version (minimal excerpt from the workflow, including upload):

```yaml
on:
  pull_request:

steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0

  - name: Run tests with Lumitrace
    env:
      LUMITRACE_GIT_DIFF: range:origin/${{ github.base_ref }}...HEAD
    run: bundle exec lumitrace -v -t --html=lumitrace_recorded.html exec rake test

  - name: Prepare Pages content
    run: |
      mkdir -p public
      cp lumitrace_recorded.html public/index.html

  - name: Upload Pages artifact
    uses: actions/upload-pages-artifact@v3
    with:
      path: public
      name: lumitrace-pages

  - name: Deploy Pages
    id: deployment
    uses: actions/deploy-pages@v4
    with:
      artifact_name: lumitrace-pages
```

The HTML report is published to: [https://ko1.github.io/lumitrace_sample_project/](https://ko1.github.io/lumitrace_sample_project/)

