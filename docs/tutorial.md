---
---

# Lumitrace Tutorial

This is a short, practical guide to using Lumitrace.

## 1. Quick Start (CLI)

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
- Skipped ranges are shown as:
  ```
  ...
  ```
- The last value is shown as `#=> ...` (with `(3rd run)` when run multiple times).

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

### Range example

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
```

Enable HTML output via env:

```bash
LUMITRACE_HTML=1 lumitrace path/to/entry.rb
LUMITRACE_HTML=/tmp/out.html lumitrace path/to/entry.rb
```

### Limit recorded values

```bash
LUMITRACE_VALUES_MAX=5 lumitrace path/to/entry.rb
```

### Limit to specific lines

```bash
lumitrace --range path/to/entry.rb:10-20,30-35 path/to/entry.rb
```

### Diff-based ranges

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

```bash
lumitrace --verbose path/to/entry.rb
```

### Write JSON too

```bash
lumitrace -j path/to/entry.rb
```

This creates `lumitrace_recorded.json`. HTML is written only when `--html` is also specified.

### Text output to stdout

```bash
lumitrace -t path/to/entry.rb
```

### Text output to a file

```bash
lumitrace --text=/tmp/lumi.txt path/to/entry.rb
```

### Text plus HTML

```bash
lumitrace -t -h path/to/entry.rb
```

### Running with exec

```bash
lumitrace --html=sample/lumitrace_rake.html exec rake
```

HTML output:
- [lumitrace_rake.html](https://ko1.github.io/lumitrace/sample/lumitrace_rake.html)

### Fork/exec merge

Fork/exec results are merged by default. The parent process writes final output; child processes only write fragments under `LUMITRACE_RESULTS_DIR`.

You can pass ranges via env (semicolon-separated):

```bash
LUMITRACE_RANGE="a.rb:1-3,5-6;b.rb" ruby your_script.rb
```

## 2. Library Mode

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

```bash
LUMITRACE_HTML=/tmp/lumi.html ruby your_script.rb
```

If you want JSON at exit:

```ruby
Lumitrace.enable!(json: true)
Lumitrace.enable!(json: "/tmp/lumi.json")
```

## 3. Diff-Based Instrumentation

Enable only lines touched by `git diff` for the current program file:

```ruby
require "lumitrace/enable_git_diff"
```

By default it uses the working tree diff. To use staged changes:

```bash
LUMITRACE_GIT_DIFF=staged ruby your_script.rb
```

### Expand the diff context

```bash
LUMITRACE_GIT_DIFF_CONTEXT=5 ruby your_script.rb
```

## 4. Root Scope

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

- If your output is large, lower `LUMITRACE_VALUES_MAX`.
- For quick checks on a single file, `enable_git_diff` keeps noise down.
