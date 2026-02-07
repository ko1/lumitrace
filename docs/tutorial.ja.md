---
---

# Lumitrace チュートリアル

ここでは Lumitrace の使い方を短く分かりやすくまとめます。

## 1. クイックスタート（CLI）

同梱の sample を最小のコマンドで実行します（テキストは stdout に出ます）:

```bash
ruby exe/lumitrace sample/sample.rb
```

プログラム本体の stdout はそのまま出力され、続けて Lumitrace のテキストが表示されます。

テキスト出力の形式:
- 各ファイルの見出しは `### path/to/file.rb`。
- 行頭に行番号が付きます（例: ` 12| `）。
- 範囲が飛ぶ場合は `...` の行が入ります。
- 最終値は `#=> ...` で表示され、複数回実行された場合は `(3rd run)` が付きます。

出力例（stdout）:

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

### ファイルに保存

同梱の sample を実行して、テキストと HTML を保存します:

```bash
ruby exe/lumitrace sample/sample.rb \
  --text sample/lumitrace_results_01.txt \
  --html sample/lumitrace_results_01.html
```

Lumitrace のテキストは `sample/lumitrace_results_01.txt`、HTML は `sample/lumitrace_results_01.html` に保存されます。

`--html PATH` を省略した場合の HTML 出力は `lumitrace_recorded.html` です。

HTML 出力を見る:
- [lumitrace_results_01.html](https://ko1.github.io/lumitrace/sample/lumitrace_results_01.html)

### 範囲指定の例

範囲を指定して、別の出力として保存します:

```bash
ruby exe/lumitrace sample/sample.rb \
  --text sample/lumitrace_results_02.txt \
  --html sample/lumitrace_results_02.html \
  --range sample/sample.rb:4-18,28-32
```

出力例（`sample/lumitrace_results_02.txt`）:

```

HTML 出力を見る:
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

環境変数で HTML を有効化:

```bash
LUMITRACE_HTML=1 ruby exe/lumitrace path/to/entry.rb
LUMITRACE_HTML=/tmp/out.html ruby exe/lumitrace path/to/entry.rb
```

### 記録する値の数を減らす

```bash
LUMITRACE_VALUES_MAX=5 ruby exe/lumitrace path/to/entry.rb
```

### 行範囲を限定する

```bash
ruby exe/lumitrace path/to/entry.rb --range path/to/entry.rb:10-20,30-35
```

### 差分だけ計測（CLI）

```bash
ruby exe/lumitrace path/to/entry.rb --git-diff
ruby exe/lumitrace path/to/entry.rb --git-diff staged
ruby exe/lumitrace path/to/entry.rb --git-diff base:HEAD~1
ruby exe/lumitrace path/to/entry.rb --git-diff-context 5
ruby exe/lumitrace path/to/entry.rb --git-cmd /usr/local/bin/git
```

未追跡ファイルを除外:

```bash
ruby exe/lumitrace path/to/entry.rb --git-diff --git-diff-no-untracked
```

### 詳細ログ

```bash
ruby exe/lumitrace path/to/entry.rb --verbose
```

### JSON も出力する

```bash
ruby exe/lumitrace path/to/entry.rb --json
```

`lumitrace_recorded.json` が生成されます（HTML は `--html` を指定したときだけ出力されます）。

### stdout にテキスト出力

```bash
ruby exe/lumitrace path/to/entry.rb --text
```

### テキストをファイルに出力

```bash
ruby exe/lumitrace path/to/entry.rb --text /tmp/lumi.txt
```

### テキストと HTML を両方出力

```bash
ruby exe/lumitrace path/to/entry.rb --text --html
```

## 2. ライブラリとして使う

終了時にテキストを出力する設定:

```ruby
require "lumitrace"
Lumitrace.enable!
```

1 行で有効化したい場合:

```ruby
require "lumitrace/enable"
```

HTML も出力したい場合:

```ruby
Lumitrace.enable!(html: true)
Lumitrace.enable!(html: "/tmp/lumi.html")
```

require だけで HTML を有効にする場合:

```ruby
ENV["LUMITRACE_HTML"] = "1"
require "lumitrace/enable"
```

require だけで JSON を有効にする場合:

```ruby
ENV["LUMITRACE_JSON"] = "1"
require "lumitrace/enable"
```

require だけでテキスト出力を制御する場合:

```ruby
ENV["LUMITRACE_TEXT"] = "0" # テキストを無効化
require "lumitrace/enable"
```

環境変数でテキストをファイルに出力:

```ruby
ENV["LUMITRACE_TEXT"] = "/tmp/lumi.txt"
require "lumitrace/enable"
```

require だけで有効化する場合:

```ruby
ENV["LUMITRACE_ENABLE"] = "1"
require "lumitrace"
```

`LUMITRACE_ENABLE` に CLI 互換のオプションを渡すこともできます:

```ruby
ENV["LUMITRACE_ENABLE"] = "--text --html /tmp/lumi.html --json"
require "lumitrace"
```

### 出力先を変更する

```bash
LUMITRACE_HTML=/tmp/lumi.html ruby your_script.rb
```

JSON を終了時に出力したい場合:

```ruby
Lumitrace.enable!(json: true)
Lumitrace.enable!(json: "/tmp/lumi.json")
```

## 3. 差分だけ計測（git diff）

現在のプログラムファイルに対する `git diff` の範囲だけを有効化します。

```ruby
require "lumitrace/enable_git_diff"
```

デフォルトは作業ツリーの差分です。ステージ済み差分を使う場合:

```bash
LUMITRACE_GIT_DIFF=staged ruby your_script.rb
```

### 差分前後の行数を広げる

```bash
LUMITRACE_GIT_DIFF_CONTEXT=5 ruby your_script.rb
```

## 4. ルート範囲

デフォルトは現在のディレクトリ配下のみ計測します。
別のルートを指定したい場合:

```bash
LUMITRACE_ROOT=/path/to/project ruby your_script.rb
```

CLI を使う場合:

```bash
lumitrace --root /path/to/project your_script.rb
```

## 5. Tips

- 出力が大きい場合は `LUMITRACE_VALUES_MAX` を下げると軽くなります。
- 1 ファイルだけの確認は `enable_git_diff` が便利です。
