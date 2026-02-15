---
---

# Lumitrace Tutorial

This is a short, practical guide to using Lumitrace.

## 1. Quick Start (CLI)

Start here to see what Lumitrace does in one command and what the default text output looks like.

Run the bundled sample with the simplest command (text output goes to stdout by default):

```bash
lumitrace sample/sample.rb
```

The program’s own stdout is still printed, and Lumitrace text output follows it.

Text output format:
- Each file header is shown like:
  ```
  ### path/to/file.rb
  ```
- Each line is prefixed with a line number like:
  ```
   12| 
  ```
- Lines where all instrumentable expressions are unexecuted are prefixed with `!`.
- Skipped ranges are shown as:
  ```
  ...
  ```
- The last value is shown as `#=> ...` (with `(3rd run)` when run multiple times).
- When printing to a TTY, long comments are truncated to the terminal width (from `COLUMNS` or `IO.console.winsize`).

Example output (stdout):

```
n0=2, n1=5, n2=11
[false, false, true]
{count: 3, max: 11, min: 2}
{even: [2], odd: [5, 11]}
"3 items, max=11"
=== Lumitrace Results (text) ===

### sample/sample.rb
 1| require './sample/sample2' #=> true
 2| require './sample/sample3' #=> true
 3| 
 4| def score(n)
 5|   base = n + 1                 #=> 3 (3rd run)
 6|   scaled = Sample2.scale(base) #=> 6 (3rd run)
 7|   squares = Sample3.series(n)  #=> [1, 4] (3rd run)
 8|   squares.sum + scaled         #=> 11 (3rd run)
 9| end
10| 
11| labels = []
12| totals = []
13| 
14| 3.times do
15|   n = it                                   #=> 2 (3rd run)
16|   total = score(n)                         #=> 11 (3rd run)
17|   labels << Sample2.format("n#{n}", total) #=> ["n0=2", "n1=5", "n2=11"] (3rd run)
18|   totals << total                          #=> [2, 5, 11] (3rd run)
19| end                                        #=> 3
20| 
21| flags = totals.map { |v| v > 5 } #=> [false, false, true]
22| stats = {
23|   count: totals.length,          #=> 3
24|   max: totals.max,               #=> 11
25|   min: totals.min                #=> 2
26| }
27| 
28| buckets = Sample3.bucketize(totals)                    #=> {even: [2], odd: [5, 11]}
29| summary = "#{stats[:count]} items, max=#{stats[:max]}" #=> 3
30| 
31| puts labels.join(", ") #=> nil
32| p flags                #=> [false, false, true]
33| p stats                #=> {count: 3, max: 11, min: 2}
34| p buckets              #=> {even: [2], odd: [5, 11]}
35| p summary              #=> 3 items, max=11

### sample/sample2.rb
 1| module Sample2
 2|   FACTOR = 2
 3| 
 4|   def self.format(label, value)
 5|     "#{label}=#{value}"         #=> 11 (3rd run)
 6|   end
 7| 
 8|   def self.scale(value)
 9|     value * FACTOR      #=> 6 (3rd run)
10|   end
11| end

### sample/sample3.rb
1| module Sample3
2|   def self.bucketize(values)
3|     values.group_by { |v| v % 2 == 0 ? :even : :odd } #=> {even: [2], odd: [5, 11]}
4|   end
5| 
6|   def self.series(n)
7|     (1..n).map { |i| i * i } #=> [1, 4] (3rd run)
8|   end
9| end
```

### Save outputs to files

Use this when you want to keep results for review or share them; it writes text and HTML outputs to disk.

Run the bundled sample and write both text and HTML outputs:

```bash
lumitrace sample/sample.rb \
  --text sample/lumitrace_results_01.txt \
  --html sample/lumitrace_results_01.html
```

The Lumitrace text output is saved in `sample/lumitrace_results_01.txt`, and the HTML is saved in `sample/lumitrace_results_01.html`.

If you run without `--html PATH`, the HTML output defaults to `lumitrace_recorded.html`.

View the HTML output:
- [lumitrace_results_01.html](https://ko1.github.io/lumitrace/sample/lumitrace_results_01.html)

HTML notes:
- Executed expressions show `🔎`; unexecuted expressions show `∅`.
- Argument values show `🧷` in HTML.
- Lines where all instrumentable expressions are unexecuted are shaded light red; mixed lines only shade the unexecuted expressions.
- When ranges are used, skipped sections are shown as `...` in the line-number column.

### Range example

When a full run is too noisy, narrow the scope to specific line ranges so you can focus on the slice you care about.

Run with ranges and save separate outputs:

```bash
lumitrace sample/sample.rb \
  --text sample/lumitrace_results_02.txt \
  --html sample/lumitrace_results_02.html \
  --range sample/sample.rb:4-18,28-32
```

Example output (`sample/lumitrace_results_02.txt`):

```

View the HTML output:
- [lumitrace_results_02.html](https://ko1.github.io/lumitrace/sample/lumitrace_results_02.html)
=== Lumitrace Results (text) ===

### sample/sample.rb (lines: 4-18, 28-32)
...
 4| def score(n)
 5|   base = n + 1                 #=> 3 (3rd run)
 6|   scaled = Sample2.scale(base) #=> 6 (3rd run)
 7|   squares = Sample3.series(n)  #=> [1, 4] (3rd run)
 8|   squares.sum + scaled         #=> 11 (3rd run)
 9| end
10| 
11| labels = []
12| totals = []
13| 
14| 3.times do
15|   n = it                                   #=> 2 (3rd run)
16|   total = score(n)                         #=> 11 (3rd run)
17|   labels << Sample2.format("n#{n}", total) #=> ["n0=2", "n1=5", "n2=11"] (3rd run)
18|   totals << total                          #=> [2, 5, 11] (3rd run)
...
28| buckets = Sample3.bucketize(totals)                    #=> {even: [2], odd: [5, 11]}
29| summary = "#{stats[:count]} items, max=#{stats[:max]}" #=> 3
30| 
31| puts labels.join(", ") #=> nil
32| p flags                #=> [false, false, true]
...
```

Enable HTML output via env:

```bash
LUMITRACE_HTML=1 lumitrace path/to/entry.rb
LUMITRACE_HTML=/tmp/out.html lumitrace path/to/entry.rb
```

### Limit recorded values

If the output is too long or slow to scan, cap how many values per line are recorded.

```bash
LUMITRACE_MAX_SAMPLES=5 lumitrace path/to/entry.rb
```

### Limit to specific lines

Use `--range` when you want precise control over which lines are traced.

```bash
lumitrace --range path/to/entry.rb:10-20,30-35 path/to/entry.rb
```

You can also pass ranges via env (semicolon-separated) when wrapping another command:

```bash
LUMITRACE_RANGE="a.rb:1-3,5-6;b.rb" ruby your_script.rb
```

### Diff-based ranges

Let Git choose the interesting lines by tracing only changes from `git diff`; this keeps review noise low.

```bash
lumitrace -g path/to/entry.rb
lumitrace --git-diff=staged path/to/entry.rb
lumitrace --git-diff=base:HEAD~1 path/to/entry.rb
lumitrace --git-diff-context 5 path/to/entry.rb
lumitrace --git-cmd /usr/local/bin/git path/to/entry.rb
```

Exclude untracked files:

```bash
lumitrace -g --git-diff-no-untracked path/to/entry.rb
```

### Verbose logs

Turn this on when you need to understand how ranges were computed or why a line was (not) recorded.

```bash
lumitrace --verbose[=LEVEL] path/to/entry.rb
```

Levels: `1` (basic), `2` (instrumented file names), `3` (instrumented source).

### Write JSON too

Use JSON output when you want to post-process results with scripts or other tools.

```bash
lumitrace -j path/to/entry.rb
```

This creates `lumitrace_recorded.json`. HTML is written only when `--html` is also specified.

### Text output to stdout

Choose this for quick, interactive feedback in your terminal.

```bash
lumitrace -t path/to/entry.rb
```

### Text output to a file

Send text output to a file when you want to archive results or attach them to CI artifacts.

```bash
lumitrace --text=/tmp/lumi.txt path/to/entry.rb
```


### Text plus HTML

Get both the fast terminal view and the richer HTML report in one run.

```bash
lumitrace -t -h path/to/entry.rb
```

### Running with exec

Wrap another command (like tests) so Lumitrace instruments what that command runs.

```bash
lumitrace --html=sample/lumitrace_rake.html exec rake
```

HTML output:
- [lumitrace_rake.html](https://ko1.github.io/lumitrace/sample/lumitrace_rake.html)

### GitHub Actions

Use CI to publish diff-scoped results automatically and share the HTML report via GitHub Pages.

For a practical CI setup (including `LUMITRACE_GIT_DIFF` and Pages upload), see `sample/sample_project/README.md`. The published Pages example is here: [https://ko1.github.io/lumitrace_sample_project/](https://ko1.github.io/lumitrace_sample_project/).

### Fork/exec merge

If your app forks or execs, this explains how Lumitrace merges results across processes.

Fork/exec results are merged by default. The parent process writes final output; child processes only write fragments under `LUMITRACE_RESULTS_DIR`.

## 2. Library Mode

Use this when you want to enable Lumitrace inside an app or script without relying on the CLI wrapper.

Enable instrumentation and text output at exit:

```ruby
require "lumitrace"
Lumitrace.enable!
```

You can also enable it via a single require:

```ruby
require "lumitrace/enable"
```

Enable HTML output too:

```ruby
Lumitrace.enable!(html: true)
Lumitrace.enable!(html: "/tmp/lumi.html")
```

Enable HTML output with a single require:

```ruby
ENV["LUMITRACE_HTML"] = "1"
require "lumitrace/enable"
```

Enable JSON output with a single require:

```ruby
ENV["LUMITRACE_JSON"] = "1"
require "lumitrace/enable"
```

Control text output with a single require:

```ruby
ENV["LUMITRACE_TEXT"] = "0" # disable text
require "lumitrace/enable"
```

Text output to a file with env:

```ruby
ENV["LUMITRACE_TEXT"] = "/tmp/lumi.txt"
require "lumitrace/enable"
```

Enable Lumitrace with a single require:

```ruby
ENV["LUMITRACE_ENABLE"] = "1"
require "lumitrace"
```

You can also pass CLI-style options via `LUMITRACE_ENABLE`:

```ruby
ENV["LUMITRACE_ENABLE"] = "-t --html=/tmp/lumi.html -j"
require "lumitrace"
```

Lumitrace also sets `RUBYOPT=-rlumitrace` to ensure exec'd Ruby processes load it, so fork/exec output can be merged.

### Change output paths

Customize where HTML/JSON/text outputs go when using library mode.

```bash
LUMITRACE_HTML=/tmp/lumi.html ruby your_script.rb
```

If you want JSON at exit:

```ruby
Lumitrace.enable!(json: true)
Lumitrace.enable!(json: "/tmp/lumi.json")
```

## 3. Diff-Based Instrumentation

Focus on just the changed lines in your codebase by wiring Lumitrace to `git diff` in library mode.

Enable only lines touched by `git diff` for the current program file:

```ruby
require "lumitrace/enable_git_diff"
```

By default it uses the working tree diff. To use staged changes:

```bash
LUMITRACE_GIT_DIFF=staged ruby your_script.rb
```

### Expand the diff context

Widen the diff window to include surrounding lines for better context.

```bash
LUMITRACE_GIT_DIFF_CONTEXT=5 ruby your_script.rb
```

## 4. Root Scope

Limit (or expand) which files are eligible for instrumentation by defining a root directory.

By default, Lumitrace only instruments files under the current directory.
Override the root with:

```bash
LUMITRACE_ROOT=/path/to/project ruby your_script.rb
```

Or when using the CLI:

```bash
lumitrace --root /path/to/project your_script.rb
```

## 5. Tips

Small knobs that keep outputs readable and noise low in day-to-day use.

- If your output is large, lower `LUMITRACE_MAX_SAMPLES`.
- For quick checks on a single file, `enable_git_diff` keeps noise down.
