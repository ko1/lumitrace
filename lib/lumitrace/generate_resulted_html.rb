require "json"

module Lumitrace
module GenerateResultedHtml
  def self.render(source_path, events_path, ranges: nil)
    unless File.exist?(events_path)
      abort "missing #{events_path}"
    end
    unless File.exist?(source_path)
      abort "missing #{source_path}"
    end

    raw_events = JSON.parse(File.read(events_path))
    events = normalize_events(raw_events)

    src_lines = File.read(source_path).lines
    ranges = normalize_ranges(ranges)

    html_lines = src_lines.each_with_index.map do |line, idx|
      lineno = idx + 1
      next if ranges && !line_in_ranges?(lineno, ranges)
      line_text = line.chomp
      evs = aggregate_events_for_line(events, lineno, line_text.length)

      if evs.empty?
        "<span class=\"line\" data-line=\"#{lineno}\"><span class=\"ln\">#{lineno}</span> #{esc(line_text)}</span>\n"
      else
        rendered = render_line_with_events(line_text, evs)
        "<span class=\"line hit\" data-line=\"#{lineno}\"><span class=\"ln\">#{lineno}</span> #{rendered}</span>\n"
      end
    end.compact

    <<~HTML
      <!doctype html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Recorded Result View</title>
        <style>
          body { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; background: #f7f5f0; color: #1f1f1f; padding: 24px; }
          .code { background: #fffdf7; border: 1px solid #e5dfd0; border-radius: 8px; padding: 16px; line-height: 1.5; }
          .line { display: inline; padding: 2px 8px; }
          .line:hover { background: #fff2c6; }
          .line.hit { background: #f0ffe7; }
          .ln { display: inline-block; width: 3em; color: #888; user-select: none; }
          .hint { color: #666; margin-bottom: 8px; }
          .expr { position: relative; display: inline-block; padding-bottom: 1px; }
          .expr.hit { }
          .expr.depth-1 { --hl: #7fbf7f; }
          .expr.depth-2 { --hl: #6fa8ff; }
          .expr.depth-3 { --hl: #ffb347; }
          .expr.depth-4 { --hl: #d78bff; }
          .expr.depth-5 { --hl: #ff6f91; }
          .expr.active { background: rgba(127, 191, 127, 0.15); box-shadow: inset 0 -2px var(--hl, #7fbf7f); }
          .marker { position: relative; display: inline-block; margin-left: 4px; cursor: help; font-size: 10px; line-height: 1; user-select: none; -webkit-user-select: none; -moz-user-select: none; }
          .marker .tooltip {
            display: none;
            position: absolute;
            left: 0;
            top: 100%;
            margin-top: 4px;
            background: #2b2b2b;
            color: #fff;
            padding: 4px 6px;
            border-radius: 4px;
            font-size: 12px;
            white-space: pre;
            min-width: 16ch;
            max-width: 90vw;
            overflow-x: auto;
            overflow-y: hidden;
            z-index: 10;
            pointer-events: auto;
          }
          .marker:hover .tooltip,
          .marker:focus-within .tooltip,
          .marker .tooltip:hover { display: block; }
        </style>
      </head>
      <body>
        <div class="hint">Hover highlighted text to see recorded values.</div>
        <pre class="code"><code>
      #{html_lines.join("")}
        </code></pre>
        <script>
          (function() {
            document.querySelectorAll('.marker').forEach(marker => {
              marker.addEventListener('mouseenter', () => {
                document.querySelectorAll('.expr').forEach(e => e.classList.remove('active'));
                marker.closest('.expr')?.classList.add('active');
              });
              marker.addEventListener('mouseleave', () => {
                marker.closest('.expr')?.classList.remove('active');
              });
            });
          })();
        </script>
      </body>
      </html>
    HTML
  end

  def self.esc(s)
    s.to_s
      .gsub("&", "&amp;")
      .gsub("<", "&lt;")
      .gsub(">", "&gt;")
      .gsub('"', "&quot;")
  end

  def self.format_value(v)
    case v
    when NilClass
      "nil"
    else
      v.to_s
    end
  end

  def self.render_line_with_events(line_text, events)
    opens = Hash.new { |h, k| h[k] = [] }
    closes = Hash.new { |h, k| h[k] = [] }

    events.each do |e|
      s = e[:start_col].to_i
      t = e[:end_col].to_i
      next if t <= s

      values = e[:values]
      total = e[:total]
      value_text = summarize_values(values, total)
      tooltip_html = esc(value_text)
      depth_class = "depth-#{e[:depth]}"
      open_tag = "<span class=\"expr hit #{depth_class}\">"
      close_tag = "<span class=\"marker\" aria-hidden=\"true\">🔎<span class=\"tooltip\">#{tooltip_html}</span></span></span>"

      len = t - s
      opens[s] << { len: len, start: s, end: t, tag: open_tag }
      closes[t] << { len: len, start: s, end: t, tag: close_tag }
    end

    positions = (opens.keys + closes.keys).uniq.sort
    out = +""
    cursor = 0

    positions.each do |pos|
      out << esc(line_text[cursor...pos]) if pos > cursor
      if closes.key?(pos)
        closes[pos].sort_by { |c| [-c[:start], c[:len]] }.each { |c| out << c[:tag] }
      end
      if opens.key?(pos)
        opens[pos].sort_by { |o| -o[:end] }.each { |o| out << o[:tag] }
      end
      cursor = pos
    end

    out << esc(line_text[cursor..]) if cursor < line_text.length
    out
  end

  def self.summarize_values(values, total = nil)
    return "" if values.nil? || values.empty?
    total ||= values.length
    last_vals = values.last(3)
    first_index = total - last_vals.length + 1
    lines = []
    extra = total - last_vals.length
    lines << "... (+#{extra} more)" if extra > 0
    last_vals.each_with_index do |v, i|
      idx = first_index + i
      lines << "##{idx}: #{format_value(v)}"
    end
    lines.join("\n")
  end

  def self.aggregate_events_for_line(events, lineno, line_len)
    buckets = {}
    spans = []

    events.each do |e|
      sline = e[:start_line]
      eline = e[:end_line]
      next if lineno < sline || lineno > eline

      if sline == eline
        s = e[:start_col]
        t = e[:end_col]
      else
        if lineno == sline
          s = e[:start_col]
          t = line_len
        elsif lineno == eline
          s = 0
          t = e[:end_col]
        else
          s = 0
          t = line_len
        end
      end

      next if t <= s
      spans << { start_col: s, end_col: t }
      buckets[e[:key]] = {
        key: e[:key],
        start_col: s,
        end_col: t,
        values: e[:values],
        total: e[:total]
      }
    end

    buckets.values.each do |b|
      depth = spans.count { |sp| b[:start_col] >= sp[:start_col] && b[:end_col] <= sp[:end_col] }
      b[:depth] = [[depth, 1].max, 5].min
    end

    buckets.values.sort_by { |b| b[:start_col] }
  end

  def self.normalize_events(events)
    merged = {}
    events.each do |e|
      file = e["file"] || e[:file]
      start_line = e["start_line"] || e[:start_line]
      start_col = e["start_col"] || e[:start_col]
      end_line = e["end_line"] || e[:end_line]
      end_col = e["end_col"] || e[:end_col]
      key = [
        file,
        start_line.to_i,
        start_col.to_i,
        end_line.to_i,
        end_col.to_i
      ]
      entry = (merged[key] ||= {
        key: key,
        file: key[0],
        start_line: key[1],
        start_col: key[2],
        end_line: key[3],
        end_col: key[4],
        values: [],
        total: 0
      })

      vals = e["values"] || e[:values] || [e["value"] || e[:value]].compact
      entry[:values].concat(vals)
      entry[:total] += (e["total"] || e[:total] || vals.length)
    end
    merged.values
  end

  def self.normalize_ranges(ranges)
    return nil unless ranges
    ranges.map do |r|
      a = (r.respond_to?(:begin) ? r.begin : r[0]).to_i
      b = (r.respond_to?(:end) ? r.end : r[1]).to_i
      a <= b ? [a, b] : [b, a]
    end
  end

  def self.normalize_ranges_by_file(input)
    return nil unless input
    input.each_with_object({}) do |(file, ranges), h|
      abs = File.expand_path(file)
      if ranges.nil? || ranges.empty?
        h[abs] = []
      else
        h[abs] = normalize_ranges(ranges)
      end
    end
  end

  def self.line_in_ranges?(line, ranges)
    return true if ranges.empty?
    ranges.any? { |(s, e)| line >= s && line <= e }
  end

  def self.render_all(events_path, root: Dir.pwd, ranges_by_file: nil)
    raw_events = JSON.parse(File.read(events_path))
    events = normalize_events(raw_events)
    render_all_from_events(events, root: root, ranges_by_file: ranges_by_file)
  end

  def self.render_all_from_events(events, root: Dir.pwd, ranges_by_file: nil)
    events = normalize_events(events)
    by_file = events.group_by { |e| e[:file] }
    ranges_by_file = normalize_ranges_by_file(ranges_by_file)

    target_paths = if ranges_by_file
      ranges_by_file.keys
    else
      by_file.keys
    end

    sections = target_paths.sort.map do |path|
      next unless File.exist?(path)
      src = File.read(path)
      ranges = ranges_by_file ? (ranges_by_file[path] || []) : nil
      html_lines = src.lines.each_with_index.map do |line, idx|
        lineno = idx + 1
        next if ranges && !line_in_ranges?(lineno, ranges)
        line_text = line.chomp
        evs = aggregate_events_for_line(by_file[path] || [], lineno, line_text.length)
        if evs.empty?
          "<span class=\"line\" data-line=\"#{lineno}\"><span class=\"ln\">#{lineno}</span> #{esc(line_text)}</span>\n"
        else
          rendered = render_line_with_events(line_text, evs)
          "<span class=\"line hit\" data-line=\"#{lineno}\"><span class=\"ln\">#{lineno}</span> #{rendered}</span>\n"
        end
      end.compact

      rel = path.start_with?(root) ? path.sub(root + File::SEPARATOR, "") : path
      <<~HTML
        <h2 class="file">#{esc(rel)}</h2>
        <pre class="code"><code>
      #{html_lines.join("")}
        </code></pre>
      HTML
    end.compact.join("\n")

    <<~HTML
      <!doctype html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Recorded Result View</title>
        <style>
          body { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; background: #f7f5f0; color: #1f1f1f; padding: 24px; }
          .code { background: #fffdf7; border: 1px solid #e5dfd0; border-radius: 8px; padding: 16px; line-height: 1.5; }
          .line { display: inline; padding: 2px 8px; }
          .line:hover { background: #fff2c6; }
          .line.hit { background: #f0ffe7; }
          .ln { display: inline-block; width: 3em; color: #888; user-select: none; }
          .hint { color: #666; margin-bottom: 8px; }
          .file { margin: 24px 0 8px; font-size: 16px; color: #333; }
          .expr { position: relative; display: inline-block; padding-bottom: 1px; }
          .expr.hit { }
          .expr.depth-1 { --hl: #7fbf7f; }
          .expr.depth-2 { --hl: #6fa8ff; }
          .expr.depth-3 { --hl: #ffb347; }
          .expr.depth-4 { --hl: #d78bff; }
          .expr.depth-5 { --hl: #ff6f91; }
          .expr.active { background: rgba(127, 191, 127, 0.15); box-shadow: inset 0 -2px var(--hl, #7fbf7f); }
          .marker { position: relative; display: inline-block; margin-left: 4px; cursor: help; font-size: 10px; line-height: 1; user-select: none; -webkit-user-select: none; -moz-user-select: none; }
          .marker .tooltip {
            display: none;
            position: absolute;
            left: 0;
            top: 100%;
            margin-top: 4px;
            background: #2b2b2b;
            color: #fff;
            padding: 4px 6px;
            border-radius: 4px;
            font-size: 12px;
            white-space: pre;
            min-width: 16ch;
            max-width: 90vw;
            overflow-x: auto;
            overflow-y: hidden;
            z-index: 10;
            pointer-events: auto;
          }
          .marker:hover .tooltip,
          .marker:focus-within .tooltip,
          .marker .tooltip:hover { display: block; }
        </style>
      </head>
      <body>
        <div class="hint">Hover highlighted text to see recorded values.</div>
        #{sections}
        <script>
          (function() {
            document.querySelectorAll('.marker').forEach(marker => {
              marker.addEventListener('mouseenter', () => {
                document.querySelectorAll('.expr').forEach(e => e.classList.remove('active'));
                marker.closest('.expr')?.classList.add('active');
              });
              marker.addEventListener('mouseleave', () => {
                marker.closest('.expr')?.classList.remove('active');
              });
            });
          })();
        </script>
      </body>
      </html>
    HTML
  end
end

if $PROGRAM_NAME == __FILE__
  source_path = ARGV[0] or abort "usage: ruby generate_resulted_html.rb SOURCE_PATH EVENTS_PATH"
  events_path = ARGV[1] or abort "usage: ruby generate_resulted_html.rb SOURCE_PATH EVENTS_PATH"
  puts GenerateResultedHtml.render(source_path, events_path)
end
end
