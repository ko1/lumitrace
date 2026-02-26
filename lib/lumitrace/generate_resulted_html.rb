require "json"
require_relative "record_instrument"

module Lumitrace
module GenerateResultedHtml
  RENDERER_JS_PATH = File.expand_path("generate_resulted_html_renderer.js", __dir__)

  def self.monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.time_step(label, logger = nil)
    start = monotonic_now
    result = yield
    elapsed_ms = (monotonic_now - start) * 1000.0
    logger&.call(format("html render: %s %.1fms", label, elapsed_ms))
    result
  end

  def self.render(source_path, events_path, ranges: nil, collect_mode: nil, max_samples: nil)
    unless File.exist?(events_path)
      abort "missing #{events_path}"
    end
    unless File.exist?(source_path)
      abort "missing #{source_path}"
    end

    raw_events = JSON.parse(File.read(events_path))
    src = File.read(source_path)
    mode_info = resolve_mode_info(raw_events, collect_mode: collect_mode, max_samples: max_samples)
    normalized_ranges = normalize_ranges(ranges)
    events = normalize_events(raw_events).select { |e| e[:file] == source_path }

    payload = build_html_payload(
      mode_info: mode_info,
      files: [
        build_html_payload_file(
          path: source_path,
          display_path: File.basename(source_path),
          source: src,
          ranges: normalized_ranges,
          trace_events: events
        )
      ]
    )

    render_payload_html(payload)
  end

  def self.esc(s)
    s.to_s
      .gsub("&", "&amp;")
      .gsub("<", "&lt;")
      .gsub(">", "&gt;")
      .gsub('"', "&quot;")
  end

  def self.build_html_payload(mode_info:, files:, command_text: nil)
    meta = {
      mode: mode_info[:mode],
      mode_text: mode_info[:text],
      max_samples: mode_info[:max_samples]
    }
    meta[:command] = command_text if command_text && !command_text.to_s.empty?
    {
      version: 1,
      meta: meta,
      files: files
    }
  end

  def self.build_html_payload_file(path:, display_path:, source:, ranges:, trace_events:, logger: nil)
    sort_start = logger ? monotonic_now : nil
    sorted_events = Array(trace_events).sort_by do |e|
      [e[:start_line].to_i, e[:start_col].to_i, e[:end_line].to_i, e[:end_col].to_i]
    end
    sort_ms = sort_start ? (monotonic_now - sort_start) * 1000.0 : nil

    map_start = logger ? monotonic_now : nil
    trace_payload = sorted_events.map { |e| event_to_html_trace_payload(e) }
    map_ms = map_start ? (monotonic_now - map_start) * 1000.0 : nil
    if logger
      logger.call(format("html render: payload_file %s sort=%.1fms map=%.1fms events=%d", display_path, sort_ms, map_ms, sorted_events.length))
    end

    {
      path: path,
      display_path: display_path,
      source: source,
      ranges: ranges,
      trace: trace_payload
    }
  end

  def self.event_to_html_trace_payload(e)
    sampled_values = e[:sampled_values]
    if (sampled_values.nil? || sampled_values.empty?) && e[:last_value]
      sampled_values = [e[:last_value]]
    end
    {
      location: [
        e[:start_line].to_i,
        e[:start_col].to_i,
        e[:end_line].to_i,
        e[:end_col].to_i
      ],
      kind: (e[:kind] || "expr").to_s,
      name: e[:name],
      sampled_values: sampled_values || [],
      types: sorted_type_counts(e[:types]),
      total: e[:total].to_i
    }
  end

  def self.payload_json_for_script(payload)
    JSON.generate(payload)
      .gsub("</", "<\\/")
      .gsub("\u2028", "\\u2028")
      .gsub("\u2029", "\\u2029")
  end

  def self.html_renderer_js
    @html_renderer_js ||= File.read(RENDERER_JS_PATH)
  end

  def self.html_report_styles
    <<~CSS
      body { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; background: #f7f5f0; color: #1f1f1f; padding: 24px; }
      .report-layout { display: grid; grid-template-columns: minmax(220px, 320px) minmax(0, 1fr); gap: 16px; align-items: start; }
      .report-layout.single-file { grid-template-columns: minmax(0, 1fr); }
      .report-sidebar { background: #fffdf7; border: 1px solid #e5dfd0; border-radius: 8px; padding: 12px; position: sticky; top: 16px; max-height: calc(100vh - 48px); overflow: hidden; }
      .report-layout.single-file .report-sidebar { display: none; }
      .tree-title { color: #444; font-size: 12px; margin-bottom: 8px; }
      .tree-scroll { overflow: auto; max-height: calc(100vh - 96px); }
      .tree-list { list-style: none; margin: 0; padding: 0; }
      .tree-list[data-level]:not([data-level="0"]) { margin-left: 14px; border-left: 1px dashed #e5dfd0; padding-left: 8px; }
      .tree-dir, .tree-file { margin: 2px 0; }
      .tree-folder { }
      .tree-folder-label { cursor: pointer; color: #4d473f; user-select: none; }
      .tree-folder-label::marker { color: #999; }
      .tree-file-btn { width: 100%; text-align: left; border: 0; background: transparent; color: #2a2a2a; padding: 4px 6px; border-radius: 6px; cursor: pointer; font: inherit; display: flex; align-items: baseline; justify-content: space-between; gap: 8px; }
      .tree-file-name { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .tree-file-meta { color: #6f6a62; font-size: 12px; white-space: nowrap; }
      .tree-file-btn:hover { background: #fff2c6; }
      .tree-file-btn.active { background: #f0ffe7; color: #1b5e3d; }
      .tree-file-btn.active .tree-file-meta { color: #1b5e3d; }
      .report-main { min-width: 0; }
      .report-main-head { display: flex; gap: 12px; align-items: center; justify-content: space-between; margin-bottom: 8px; }
      .current-file { color: #333; font-size: 13px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .report-viewer { min-width: 0; }
      .file-section { min-width: 0; }
      .code { background: #fffdf7; border: 1px solid #e5dfd0; border-radius: 8px; padding: 16px; line-height: 1.5; }
      .line { display: block; box-sizing: border-box; padding: 2px 8px; }
      .line:hover { background: #fff2c6; }
      .line.hit { background: #f0ffe7; }
      .line.miss { background: #ffecec; }
      .line.line-target { box-shadow: inset 3px 0 #2f6f8e; background: #e9f4fb; }
      .line.ellipsis { color: #999; }
      .ln { display: inline-block; width: 3em; color: #888; user-select: none; }
      .ln-link { color: inherit; text-decoration: none; }
      .ln-link:hover { text-decoration: underline; color: #2f6f8e; }
      .hint { color: #666; margin-bottom: 4px; }
      .command { color: #555; margin-bottom: 4px; font-size: 12px; overflow-wrap: anywhere; }
      .mode { color: #444; margin-bottom: 8px; }
      .report-footer { margin-top: 16px; color: #666; font-size: 12px; }
      .report-footer a { color: #2f6f8e; text-decoration: none; }
      .report-footer a:hover { text-decoration: underline; }
      .file { margin: 24px 0 8px; font-size: 16px; color: #333; }
      .expr { position: relative; display: inline-block; padding-bottom: 1px; }
      .expr.hit { }
      .expr.depth-1 { --hl: #7fbf7f; }
      .expr.depth-2 { --hl: #6fa8ff; }
      .expr.depth-3 { --hl: #ffb347; }
      .expr.depth-4 { --hl: #d78bff; }
      .expr.depth-5 { --hl: #ff6f91; }
      .expr.active { background: rgba(127, 191, 127, 0.15); box-shadow: inset 0 -2px var(--hl, #7fbf7f); }
      .expr.miss { background: rgba(255, 120, 120, 0.18); box-shadow: inset 0 -2px rgba(200, 120, 120, 0.6); }
      .marker { position: relative; display: inline-block; margin-left: 4px; cursor: help; font-size: 10px; line-height: 1; user-select: none; -webkit-user-select: none; -moz-user-select: none; }
      .marker.miss { color: #c07070; }
      .marker.arg { color: #2f6f8e; }
      .marker .tooltip {
        display: none;
        position: absolute;
        left: 0;
        bottom: 100%;
        margin-bottom: 6px;
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
      .noscript { color: #666; }
      @media (max-width: 900px) {
        body { padding: 16px; }
        .report-layout { grid-template-columns: 1fr; }
        .report-sidebar { position: static; max-height: none; }
        .tree-scroll { max-height: 220px; }
        .report-main-head { flex-direction: column; align-items: flex-start; }
      }
    CSS
  end

  def self.footer_version_suffix
    return "" unless defined?(Lumitrace::VERSION) && Lumitrace::VERSION
    " v#{Lumitrace::VERSION}"
  end

  def self.render_payload_html(payload)
    <<~HTML
      <!doctype html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Recorded Result View</title>
        <style>
      #{html_report_styles}
        </style>
      </head>
      <body>
        <div id="lumitrace-app"></div>
        <div class="report-footer">Generated by <a href="https://ko1.github.io/lumitrace/" target="_blank" rel="noopener noreferrer">lumitrace</a>#{footer_version_suffix}.</div>
        <noscript><p class="noscript">Lumitrace HTML report requires JavaScript to render the source and trace view.</p></noscript>
        <script id="lumitrace-payload" type="application/json">#{payload_json_for_script(payload)}</script>
        <script>
      #{html_renderer_js}
        </script>
      </body>
      </html>
    HTML
  end

  def self.detect_collect_mode(events)
    arr = Array(events)
    return "history" if arr.any? { |e| e.key?(:sampled_values) || e.key?("sampled_values") }
    return "last" if arr.any? { |e| e.key?(:last_value) || e.key?("last_value") }
    "types"
  end

  def self.infer_max_samples(events)
    max = Array(events).map do |e|
      values = e[:sampled_values] || e["sampled_values"]
      values.is_a?(Array) ? values.length : nil
    end.compact.max
    max && max > 0 ? max : nil
  end

  def self.resolve_mode_info(events, collect_mode: nil, max_samples: nil)
    mode = collect_mode.to_s.strip
    mode = detect_collect_mode(events) if mode.empty?
    samples = max_samples
    if mode == "history" && (samples.nil? || samples.to_i <= 0)
      samples = infer_max_samples(events)
    end
    text = case mode
    when "history"
      n = samples && samples.to_i > 0 ? samples.to_i : "N"
      unit = n == 1 ? "sample" : "samples"
      "Mode: history (last #{n} #{unit})"
    when "types"
      "Mode: types (type counts)"
    else
      "Mode: last (last value)"
    end
    { mode: mode, max_samples: samples, text: text }
  end

  def self.format_value(v, type: nil)
    value = case v
    when NilClass
      "nil"
    else
      v.to_s
    end
    type ||= value_type_name(v)
    "#{value} (#{type})"
  end

  def self.type_list_text(types, only_if_multiple: false)
    counts = normalize_type_counts(types)
    return nil if only_if_multiple && counts.length <= 1
    return "(no types)" if counts.empty?
    text = counts.sort_by { |k, _v| k }.map { |k, v| "#{k}(#{v})" }.join(", ")
    "types: #{text}"
  end

  def self.last_value_to_pair(last_value)
    return [nil, nil] unless last_value
    return [last_value, nil] unless last_value.is_a?(Hash)
    type = last_value[:type] || last_value["type"]
    if last_value.key?(:value) || last_value.key?("value")
      [last_value[:value] || last_value["value"], type]
    elsif last_value.key?(:preview) || last_value.key?("preview")
      [last_value[:preview] || last_value["preview"], type]
    elsif last_value.key?(:inspect) || last_value.key?("inspect")
      [last_value[:inspect] || last_value["inspect"], type]
    else
      [last_value.inspect, type]
    end
  end

  def self.value_type_name(v)
    name = v.class.name
    name && !name.empty? ? name : v.class.to_s
  end

  def self.render_line_with_events(line_text, events)
    opens = Hash.new { |h, k| h[k] = [] }
    closes = Hash.new { |h, k| h[k] = [] }

    events.each do |e|
      s = e[:start_col].to_i
      t = e[:end_col].to_i
      next if t <= s

      values = e[:sampled_values]
      all_types = e[:types]
      total = e[:total]
      label = if e[:kind].to_s == "arg" && e[:name]
        "arg #{e[:name]}"
      else
        nil
      end
      value_text = if total.to_i == 0
        label ? "#{label}: (not hit)" : "(not hit)"
      else
        summary = summarize_values(values, total, all_types: all_types)
        if label
          summary.empty? ? label : "#{label}: #{summary}"
        else
          summary
        end
      end
      tooltip_html = esc(value_text)
      depth_class = "depth-#{e[:depth]}"
      miss_class = total.to_i == 0 && !e[:suppress_miss] ? " miss" : ""
      key_attr = esc(e[:key_id])
      open_tag = "<span class=\"expr hit #{depth_class}#{miss_class}\" data-key=\"#{key_attr}\">"
      if e.fetch(:marker, true)
        marker = if total.to_i == 0
          "∅"
        elsif e[:kind].to_s == "arg"
          "🧷"
        else
          "🔎"
        end
        marker_class = "marker"
        marker_class = "marker miss" if total.to_i == 0 && !e[:suppress_miss]
        marker_class = "#{marker_class} arg" if e[:kind].to_s == "arg"
        close_tag = "<span class=\"#{marker_class}\" data-key=\"#{key_attr}\" aria-hidden=\"true\">#{marker}<span class=\"tooltip\">#{tooltip_html}</span></span></span>"
      else
        close_tag = "</span>"
      end

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

  def self.comment_value_with_total_for_line(events)
    best = best_event_for_line(events)
    return nil unless best
    return nil if best[:total].to_i <= 0

    sampled_last = best[:sampled_values]&.last
    v, t = last_value_to_pair(sampled_last)
    all_types = best[:types]
    show_single_type = best[:sampled_values].nil? || best[:sampled_values].empty?
    type_text = type_list_text(all_types, only_if_multiple: !show_single_type)
    total = best[:total]
    value = if show_single_type
      type_text || ""
    else
      base = format_value(v, type: t)
      type_text ? "#{base} #{type_text}" : base
    end
    return nil if value.empty?
    if total && total > 1
      "#{value} (#{ordinal(total)} run)"
    else
      value
    end
  end

  def self.ordinal(n)
    n = n.to_i
    return n.to_s if n <= 0
    mod100 = n % 100
    suffix = if mod100 >= 11 && mod100 <= 13
      "th"
    else
      case n % 10
      when 1 then "st"
      when 2 then "nd"
      when 3 then "rd"
      else "th"
      end
    end
    "#{n}#{suffix}"
  end

  def self.best_event_for_line(events)
    return nil if events.empty?

    candidates = events.select { |e| e[:marker] && e[:kind].to_s != "arg" }
    return nil if candidates.empty?

    candidates.max_by do |e|
      span = e[:end_col].to_i - e[:start_col].to_i
      [span, e[:end_col].to_i, -e[:start_col].to_i]
    end
  end

  def self.summarize_values(values, total = nil, all_types: nil)
    if values.nil? || values.empty?
      multi = type_list_text(all_types, only_if_multiple: false)
      return multi if multi
      return ""
    end
    total ||= values.length
    last_vals = values.last(3)
    first_index = total - last_vals.length + 1
    lines = []
    extra = total - last_vals.length
    lines << "... (+#{extra} more)" if extra > 0
    last_vals.each_with_index do |v, i|
      idx = first_index + i
      value_text, type_text = last_value_to_pair(v)
      lines << "##{idx}: #{format_value(value_text, type: type_text)}"
    end
    multi = type_list_text(all_types, only_if_multiple: true)
    lines << multi if multi
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
        marker = true
      else
        if lineno == sline
          s = e[:start_col]
          t = line_len
          marker = false
        elsif lineno == eline
          s = 0
          t = e[:end_col]
          marker = true
        else
          s = 0
          t = line_len
          marker = false
        end
      end

      next if t <= s
      spans << { start_col: s, end_col: t }
      event_key = e[:key] || [
        e[:file],
        e[:start_line].to_i,
        e[:start_col].to_i,
        e[:end_line].to_i,
        e[:end_col].to_i
      ]
      key_id = event_key.join(":")
      buckets[event_key] = {
        key: event_key,
        key_id: key_id,
        start_col: s,
        end_col: t,
        marker: marker,
        kind: e[:kind],
        name: e[:name],
        sampled_values: e[:sampled_values],
        types: e[:types],
        total: e[:total]
      }
    end

    buckets.values.each do |b|
      depth = spans.count { |sp| b[:start_col] >= sp[:start_col] && b[:end_col] <= sp[:end_col] }
      b[:depth] = [[depth, 1].max, 5].min
    end

    buckets.values.sort_by { |b| b[:start_col] }
  end

  def self.line_class_for(expected, executed)
    return " hit" if executed > 0
    return " miss" if expected > 0
    ""
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
      kind = e["kind"] || e[:kind] || "expr"
      name = e["name"] || e[:name]
      entry = (merged[key] ||= {
        key: key,
        file: key[0],
        start_line: key[1],
        start_col: key[2],
        end_line: key[3],
        end_col: key[4],
        kind: kind,
        name: name,
        sampled_values: [],
        types: {},
        total: 0
      })

      vals = e["sampled_values"] || e[:sampled_values] || []
      entry[:sampled_values].concat(vals)
      normalize_type_counts(e["types"] || e[:types]).each do |t, c|
        entry[:types][t] = (entry[:types][t] || 0) + c
      end
      if vals.empty?
        last_value = e["last_value"] || e[:last_value]
        entry[:sampled_values] << last_value if last_value
      end
      entry[:total] += (e["total"] || e[:total] || vals.length)
    end
    merged.each_value { |v| v[:types] = sorted_type_counts(v[:types]) }
    merged.values
  end

  def self.normalize_type_counts(types)
    return {} unless types
    case types
    when Hash
      out = {}
      types.each do |k, v|
        key = k.to_s
        next if key.empty?
        count = v.to_i
        count = 1 if count <= 0
        out[key] = (out[key] || 0) + count
      end
      out
    else
      arr = types.is_a?(String) ? [types] : Array(types)
      out = {}
      arr.each do |t|
        key = t.to_s
        next if key.empty?
        out[key] = (out[key] || 0) + 1
      end
      out
    end
  end

  def self.sorted_type_counts(types)
    normalize_type_counts(types).sort_by { |k, _v| k }.to_h
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

  def self.line_stats(source, ranges, events, filename)
    expected_by_line = Hash.new(0)
    RecordInstrument.collect_locations_from_source(source, ranges || []).each do |loc|
      (loc[:start_line]..loc[:end_line]).each do |line|
        expected_by_line[line] += 1
      end
    end
    executed_by_line = Hash.new(0)
    seen = {}
    events.each do |e|
      next unless e[:file] == filename
      key = [e[:start_line], e[:start_col], e[:end_line], e[:end_col]]
      next if seen[key]
      seen[key] = true
      if e[:total].to_i > 0
        (e[:start_line]..e[:end_line]).each do |line|
          executed_by_line[line] += 1
        end
      end
    end
    [expected_by_line, executed_by_line]
  end

  def self.render_all(events_path, root: Dir.pwd, ranges_by_file: nil, collect_mode: nil, max_samples: nil, logger: nil, command_text: nil)
    raw_events = JSON.parse(File.read(events_path))
    render_all_from_events(
      raw_events,
      root: root,
      ranges_by_file: ranges_by_file,
      collect_mode: collect_mode,
      max_samples: max_samples,
      logger: logger,
      command_text: command_text
    )
  end

  def self.render_all_from_events(events, root: Dir.pwd, ranges_by_file: nil, collect_mode: nil, max_samples: nil, logger: nil, command_text: nil)
    normalized = time_step("normalize_events", logger) { normalize_events(events) }
    render_all_from_normalized_events(
      normalized,
      root: root,
      ranges_by_file: ranges_by_file,
      collect_mode: collect_mode,
      max_samples: max_samples,
      logger: logger,
      command_text: command_text
    )
  end

  def self.render_all_from_normalized_events(events, root: Dir.pwd, ranges_by_file: nil, collect_mode: nil, max_samples: nil, logger: nil, command_text: nil)
    total_start = monotonic_now

    mode_info = time_step("resolve_mode", logger) do
      resolve_mode_info(events, collect_mode: collect_mode, max_samples: max_samples)
    end
    by_file = time_step("group_by_file", logger) { events.group_by { |e| e[:file] } }
    ranges_by_file = time_step("normalize_ranges_by_file", logger) { normalize_ranges_by_file(ranges_by_file) }

    files = []
    by_file.keys.sort.each do |path|
      next unless File.exist?(path)
      file_start = monotonic_now
      read_start = logger ? monotonic_now : nil
      src = File.read(path)
      read_ms = read_start ? (monotonic_now - read_start) * 1000.0 : nil
      if ranges_by_file
        next unless ranges_by_file.key?(path)
        ranges = ranges_by_file[path] || []
      else
        ranges = nil
      end
      rel = path.start_with?(root) ? path.sub(root + File::SEPARATOR, "") : path
      select_start = logger ? monotonic_now : nil
      file_events = by_file[path] || []
      select_ms = select_start ? (monotonic_now - select_start) * 1000.0 : nil
      payload_file_start = logger ? monotonic_now : nil
      files << build_html_payload_file(
        path: path,
        display_path: rel,
        source: src,
        ranges: ranges,
        trace_events: file_events,
        logger: logger
      )
      payload_file_ms = payload_file_start ? (monotonic_now - payload_file_start) * 1000.0 : nil
      if logger
        elapsed_ms = (monotonic_now - file_start) * 1000.0
        logger.call(format("html render: file %s read=%.1fms select=%.1fms payload=%.1fms events=%d bytes=%d total=%.1fms", rel, read_ms, select_ms, payload_file_ms, file_events.length, src.bytesize, elapsed_ms))
      end
    end

    payload = time_step("build_payload", logger) { build_html_payload(mode_info: mode_info, files: files, command_text: command_text) }
    html = time_step("render_payload_html", logger) { render_payload_html(payload) }
    if logger
      total_ms = (monotonic_now - total_start) * 1000.0
      logger.call(format("html render: total files=%d events=%d html_bytes=%d %.1fms", files.length, events.length, html.bytesize, total_ms))
    end
    html
  end

  def self.render_source_from_events(source, events, filename: "script.rb", ranges: nil, collect_mode: nil, max_samples: nil, command_text: nil)
    render_source_from_normalized_events(
      source,
      normalize_events(events),
      filename: filename,
      ranges: ranges,
      collect_mode: collect_mode,
      max_samples: max_samples,
      command_text: command_text
    )
  end

  def self.render_source_from_normalized_events(source, events, filename: "script.rb", ranges: nil, collect_mode: nil, max_samples: nil, command_text: nil)
    mode_info = resolve_mode_info(events, collect_mode: collect_mode, max_samples: max_samples)
    ranges = normalize_ranges(ranges)
    target_events = events.select { |e| e[:file] == filename }

    payload = build_html_payload(
      mode_info: mode_info,
      command_text: command_text,
      files: [
        build_html_payload_file(
          path: filename,
          display_path: filename,
          source: source,
          ranges: ranges,
          trace_events: target_events
        )
      ]
    )

    render_payload_html(payload)
  end

  def self.render_text_from_events(source, events, filename: "script.rb", ranges: nil, with_header: true, header_label: nil, tty: nil)
    render_text_from_normalized_events(
      source,
      normalize_events(events),
      filename: filename,
      ranges: ranges,
      with_header: with_header,
      header_label: header_label,
      tty: tty
    )
  end

  def self.render_text_from_normalized_events(source, events, filename: "script.rb", ranges: nil, with_header: true, header_label: nil, tty: nil)
    ranges = normalize_ranges(ranges)
    target_events = events.select { |e| e[:file] == filename }
    term_width = tty ? terminal_width : nil
    def_lines = RecordInstrument.definition_lines_from_source(source, ranges)

    expected_by_line = Hash.new(0)
    RecordInstrument.collect_locations_from_source(source, ranges).each do |loc|
      expected_by_line[loc[:start_line]] += 1
    end
    executed_by_line = Hash.new(0)
    seen = {}
    target_events.each do |e|
      line = e[:start_line] || e["start_line"]
      key = [
        e[:start_line] || e["start_line"],
        e[:start_col] || e["start_col"],
        e[:end_line] || e["end_line"],
        e[:end_col] || e["end_col"]
      ]
      next if seen[key]
      seen[key] = true
      executed_by_line[line] += 1 if line && (e[:total] || e["total"]).to_i > 0
    end

    out = +""
    if with_header
      label = header_label || filename
      if ranges && !ranges.empty?
        label = "#{label} (lines: #{format_ranges(ranges)})"
      end
      out << "### #{label}\n"
    end

    total_lines = source.lines.length
    ln_width = total_lines.to_s.length
    prefix_for = ->(n, missing) { "#{missing ? "!" : " "}#{format("%#{ln_width}d| ", n)}" }

    raw_lines = source.lines.each_with_index.flat_map do |line, idx|
      lineno = idx + 1
      next if ranges && !line_in_ranges?(lineno, ranges)
      line_text = line.chomp
      evs = aggregate_events_for_line(target_events, lineno, line_text.length)
      def_info = def_lines[lineno]
      comment_value = def_info && !def_info[:endless] ? nil : comment_value_with_total_for_line(evs)
      missing = expected_by_line[lineno] > 0 && executed_by_line[lineno] == 0
      [{ lineno: lineno, text: line_text, comment: comment_value, prefix: prefix_for.call(lineno, missing) }]
    end.compact

    group = []
    flush_group = lambda do
      return if group.empty?
      max_len = group.map { |l| l[:text].length }.max || 0
      group.each do |l|
        if l[:comment] && !l[:comment].to_s.empty?
          pad = " " * (max_len - l[:text].length)
          line_prefix = "#{l[:prefix]}#{l[:text]}#{pad} #=> "
          comment = l[:comment].to_s
          if term_width && term_width > 0
            available = term_width - line_prefix.length
            if available > 0
              if comment.length > available
                if available >= 3
                  comment = comment[0, available - 3] + "..."
                else
                  comment = comment[0, available]
                end
              end
              out << "#{line_prefix}#{comment}\n"
            else
              out << "#{l[:prefix]}#{l[:text]}\n"
            end
          else
            out << "#{line_prefix}#{comment}\n"
          end
        else
          out << "#{l[:prefix]}#{l[:text]}\n"
        end
      end
      group.clear
    end

    prev_lineno = nil
    first_lineno = raw_lines.first && raw_lines.first[:lineno]
    last_lineno = raw_lines.last && raw_lines.last[:lineno]
    if first_lineno && first_lineno > 1
      out << "...\n"
    end
    raw_lines.each do |l|
      if prev_lineno && l[:lineno] > prev_lineno + 1
        flush_group.call
        out << "...\n"
      end
      if l[:text].strip.empty?
        flush_group.call
        out << "#{l[:prefix]}#{l[:text]}\n"
      else
        group << l
      end
      prev_lineno = l[:lineno]
    end
    flush_group.call
    if last_lineno
      total_lines = source.lines.length
      out << "...\n" if last_lineno < total_lines
    end

    out
  end

  def self.terminal_width
    cols = ENV["COLUMNS"].to_i
    return cols if cols > 0
    begin
      require "io/console"
      return IO.console.winsize[1] if IO.respond_to?(:console) && IO.console
    rescue StandardError
      nil
    end
    nil
  end

  def self.render_text_all_from_events(events, root: Dir.pwd, ranges_by_file: nil, tty: nil)
    render_text_all_from_normalized_events(normalize_events(events), root: root, ranges_by_file: ranges_by_file, tty: tty)
  end

  def self.render_text_all_from_normalized_events(events, root: Dir.pwd, ranges_by_file: nil, tty: nil)
    by_file = events.group_by { |e| e[:file] }
    ranges_by_file = normalize_ranges_by_file(ranges_by_file)

    sections = by_file.keys.sort.map do |path|
      next unless File.exist?(path)
      src = File.read(path)
      if ranges_by_file
        next unless ranges_by_file.key?(path)
        ranges = ranges_by_file[path] || []
      else
        ranges = nil
      end
      rel = path.start_with?(root) ? path.sub(root + File::SEPARATOR, "") : path
      render_text_from_normalized_events(src, events, filename: path, ranges: ranges, with_header: true, header_label: rel, tty: tty)
    end.compact

    header = "\n=== Lumitrace Results (text) ===\n\n"
    header + sections.join("\n")
  end

  def self.format_ranges(ranges)
    ranges.map { |(s, e)| s == e ? s.to_s : "#{s}-#{e}" }.join(", ")
  end
end

if $PROGRAM_NAME == __FILE__
  source_path = ARGV[0] or abort "usage: ruby generate_resulted_html.rb SOURCE_PATH EVENTS_PATH"
  events_path = ARGV[1] or abort "usage: ruby generate_resulted_html.rb SOURCE_PATH EVENTS_PATH"
  puts GenerateResultedHtml.render(source_path, events_path)
end
end
