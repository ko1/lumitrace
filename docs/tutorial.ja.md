---
---

# Lumitrace チュートリアル

ここでは Lumitrace の使い方を短く分かりやすくまとめます。

## 1. クイックスタート（CLI）

まずは最小のコマンドで動かして、出力形式の雰囲気を掴みます。

同梱の sample を最小のコマンドで実行します（テキストは stdout に出ます）:

```bash
lumitrace sample/sample.rb
```

プログラム本体の stdout はそのまま出力され、続けて Lumitrace のテキストが表示されます。

テキスト出力の形式:
- 各ファイルの見出しは次のように表示されます:
  ```
  ### path/to/file.rb
  ```
- 行頭に行番号が付きます（例）:
  ```
   12| 
  ```
- 記録対象の式がすべて未実行の行は `!` が付きます。
- 範囲が飛ぶ場合は次の行が入ります:
  ```
  ...
  ```
- 最終値は `#=> ...` で表示され、複数回実行された場合は `(3rd run)` が付きます。
- TTY に出力する場合、長いコメントは端末幅（`COLUMNS` または `IO.console.winsize`）に合わせて省略されます。

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

結果をあとで見返したり共有したいときは、テキストと HTML をディスクに書き出すのが便利です。

同梱の sample を実行して、テキストと HTML を保存します:

```bash
lumitrace sample/sample.rb \
  --text sample/lumitrace_results_01.txt \
  --html sample/lumitrace_results_01.html
```

Lumitrace のテキストは `sample/lumitrace_results_01.txt`、HTML は `sample/lumitrace_results_01.html` に保存されます。

`--html PATH` を省略した場合の HTML 出力は `lumitrace_recorded.html` です。

HTML 出力を見る:
- [lumitrace_results_01.html](https://ko1.github.io/lumitrace/sample/lumitrace_results_01.html)

HTML について:
- 実行済みの式は `🔎`、未実行の式は `∅` で表示されます。
- 引数の値は HTML では `🧷` で表示されます。
- 記録対象の式がすべて未実行の行は薄い赤で表示され、混在行では未実行の式のみ薄赤になります。
- 範囲指定時の省略は行番号欄に `...` が入ります。

### 範囲指定の例

出力が多いときは、対象行を絞って読みやすくします。

範囲を指定して、別の出力として保存します:

```bash
lumitrace sample/sample.rb \
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

環境変数で HTML を有効化:

```bash
LUMITRACE_HTML=1 lumitrace path/to/entry.rb
LUMITRACE_HTML=/tmp/out.html lumitrace path/to/entry.rb
```

### 記録する値の数を減らす

出力が長すぎたり読みづらいときに、1 行あたりの記録数を制限します。

```bash
LUMITRACE_MAX_SAMPLES=5 lumitrace path/to/entry.rb
```

### 行範囲を限定する

特定の行だけを明示的に追いたいときの指定です。

```bash
lumitrace --range path/to/entry.rb:10-20,30-35 path/to/entry.rb
```

別コマンドをラップするときは、環境変数で range を渡せます（`;` 区切り）:

```bash
LUMITRACE_RANGE="a.rb:1-3,5-6;b.rb" ruby your_script.rb
```

### 差分だけ計測（CLI）

変更行だけを自動で追うと、レビュー時のノイズが減ります。

```bash
lumitrace -g path/to/entry.rb
lumitrace --git-diff=staged path/to/entry.rb
lumitrace --git-diff=base:HEAD~1 path/to/entry.rb
lumitrace --git-diff-context 5 path/to/entry.rb
lumitrace --git-cmd /usr/local/bin/git path/to/entry.rb
```

未追跡ファイルを除外:

```bash
lumitrace -g --git-diff-no-untracked path/to/entry.rb
```

### 詳細ログ

レンジ計算や動作の理由を追いたいときに有効です。

```bash
lumitrace --verbose[=LEVEL] path/to/entry.rb
```

レベル: `1`（基本ログ）、`2`（変換したファイル名）、`3`（変換後ソース）。

### JSON も出力する

ツール連携や後処理のために JSON を出します。

```bash
lumitrace -j path/to/entry.rb
```

`lumitrace_recorded.json` が生成されます（HTML は `--html` を指定したときだけ出力されます）。

### stdout にテキスト出力

端末でさっと確認したいとき向けです。

```bash
lumitrace -t path/to/entry.rb
```

### テキストをファイルに出力

CI アーティファクトなどに残したいときに便利です。

```bash
lumitrace --text=/tmp/lumi.txt path/to/entry.rb
```


### テキストと HTML を両方出力

素早い確認と詳細閲覧を一回で得たいときに使います。

```bash
lumitrace -t -h path/to/entry.rb
```

### exec で実行

テストなど別コマンドをラップして計測します。

```bash
lumitrace --html=sample/lumitrace_rake.html exec rake
```

HTML 出力:
- [lumitrace_rake.html](https://ko1.github.io/lumitrace/sample/lumitrace_rake.html)

### GitHub Actions

CI で差分ログを出し、Pages で HTML を共有したいときの導線です。

GitHub Actions への追加手順（`LUMITRACE_GIT_DIFF` や Pages へのアップロード設定を含む）は `sample/sample_project/README.md` を参照してください。公開済み Pages はこちらです:
[https://ko1.github.io/lumitrace_sample_project/](https://ko1.github.io/lumitrace_sample_project/)

### Fork/exec のマージ

プロセスが増える構成のとき、結果がどう合流するかを押さえます。

fork/exec の結果はデフォルトでマージされます。親プロセスが最終出力を行い、子プロセスは `LUMITRACE_RESULTS_DIR` に断片 JSON を保存します。

### AI と使う

AI に読ませる前提なら、次の順番にすると効率が良いです。

1. まず型分布だけ取る（安く全体像を見る）

```bash
lumitrace --collect-mode types -j path/to/entry.rb
```

2. 次に最終値を見る（値の当たりを付ける）

```bash
lumitrace --collect-mode last -j path/to/entry.rb
```

3. 変化が必要な箇所だけ履歴を見る

```bash
lumitrace --collect-mode history --max-samples 5 -j path/to/entry.rb
```

4. 対象を絞る（トークン節約）

```bash
lumitrace --collect-mode last -j --range path/to/entry.rb:120-180 path/to/entry.rb
lumitrace --collect-mode last -j -g path/to/entry.rb
```

補助情報は `lumitrace help --format json` と `lumitrace schema --format json` で機械可読に取得できます。

## 2. ライブラリとして使う

CLI を使わずアプリに組み込みたい場合はここから始めます。

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
ENV["LUMITRACE_ENABLE"] = "-t --html=/tmp/lumi.html -j"
require "lumitrace"
```

exec 先でも読み込まれるように、Lumitrace は `RUBYOPT=-rlumitrace` を設定します。これにより fork/exec の結果をマージできます。

### 出力先を変更する

用途に合わせて HTML/JSON/テキストの保存先を変えられます。

```bash
LUMITRACE_HTML=/tmp/lumi.html ruby your_script.rb
```

JSON を終了時に出力したい場合:

```ruby
Lumitrace.enable!(json: true)
Lumitrace.enable!(json: "/tmp/lumi.json")
```

## 3. 差分だけ計測（git diff）

ライブラリ側で `git diff` に連動させ、変更行だけを追う方法です。

現在のプログラムファイルに対する `git diff` の範囲だけを有効化します。

```ruby
require "lumitrace/enable_git_diff"
```

デフォルトは作業ツリーの差分です。ステージ済み差分を使う場合:

```bash
LUMITRACE_GIT_DIFF=staged ruby your_script.rb
```

### 差分前後の行数を広げる

前後の文脈も含めたいときに範囲を広げます。

```bash
LUMITRACE_GIT_DIFF_CONTEXT=5 ruby your_script.rb
```

## 4. ルート範囲

計測対象のディレクトリ範囲を明確にしたいときに使います。

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

日常的に効く小さなコツをまとめます。

- 出力が大きい場合は `LUMITRACE_MAX_SAMPLES` を下げると軽くなります。
- 1 ファイルだけの確認は `enable_git_diff` が便利です。
