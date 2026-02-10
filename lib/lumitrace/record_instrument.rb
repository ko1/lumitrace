require "json"
require "prism"

module Lumitrace
  def self.R(id, value)
    events_by_id = RecordInstrument.events_by_id
    entry = events_by_id[id]
    if entry
      max = entry.length - 2
      idx = entry[max]
      entry[idx] = value
      entry[max] = (idx + 1) % max
      entry[max + 1] += 1
    else
      max = RecordInstrument.max_values_per_expr
      entry = Array.new(max + 2)
      entry[max] = 1
      entry[max + 1] = 1
      entry[0] = value
      events_by_id[id] = entry
    end
    value
  end

module RecordInstrument
  SKIP_NODE_CLASSES = [
    Prism::DefNode,
    Prism::ClassNode,
    Prism::ModuleNode,
    Prism::IfNode,
    Prism::UnlessNode,
    Prism::WhileNode,
    Prism::UntilNode,
    Prism::ForNode,
    Prism::CaseNode,
    Prism::BeginNode,
    Prism::RescueNode,
    Prism::EnsureNode,
    Prism::AliasMethodNode,
    Prism::UndefNode
  ].freeze

  LITERAL_NODE_CLASSES = [
    Prism::IntegerNode,
    Prism::FloatNode,
    Prism::RationalNode,
    Prism::ImaginaryNode,
    Prism::StringNode,
    Prism::SymbolNode,
    Prism::TrueNode,
    Prism::FalseNode,
    Prism::NilNode
  ].freeze

  WRAP_NODE_CLASSES = [
    Prism::CallNode,
    Prism::LocalVariableReadNode,
    Prism::ItLocalVariableReadNode,
    Prism::ConstantReadNode,
    Prism::InstanceVariableReadNode,
    Prism::ClassVariableReadNode,
    Prism::GlobalVariableReadNode
  ].freeze

  def self.instrument_source(src, ranges, file_label: nil, record_method: "Lumitrace::R")
    file_label ||= "(unknown)"
    ranges = normalize_ranges(ranges)

    parse = Prism.parse(src)
    if parse.errors.any?
      raise "parse errors: #{parse.errors.map(&:message).join(", ") }"
    end

    inserts = collect_inserts(parse.value, src, ranges, file_label, record_method)

    modified = apply_insertions(src, inserts)
    if Lumitrace.respond_to?(:verbose_level) && Lumitrace.verbose_level >= 2
      Lumitrace.verbose_log("instrumented: #{file_label}", level: 2)
      if Lumitrace.verbose_level >= 3
        Lumitrace.verbose_log("instrumented_source: #{file_label}\n#{with_line_numbers(modified)}", level: 3)
      end
    end
    modified
  end

  def self.with_line_numbers(source)
    lines = source.lines
    width = lines.length.to_s.length
    lines.each_with_index.map do |line, idx|
      format("%#{width}d| %s", idx + 1, line)
    end.join
  end

  def self.collect_inserts(root, src, ranges, file_label, record_method)
    inserts = []
    stack = [[root, nil]]

    until stack.empty?
      node, parent = stack.pop
      next unless node

      if node.respond_to?(:location)
        line = node.location.start_line
        if in_ranges?(line, ranges) && wrap_expr?(node, parent)
          loc = expr_location(node)
          id = register_location(file_label, loc)
          prefix = "#{record_method}(#{id}, ("
          suffix = "))"
          span_len = loc[:end_offset] - loc[:start_offset]
          inserts << { pos: loc[:start_offset], text: prefix, kind: :open, len: span_len }
          inserts << { pos: loc[:end_offset], text: suffix, kind: :close, len: span_len }
        end
      end

      node.child_nodes.each { |child| stack << [child, node] }
    end

    inserts
  end

  def self.normalize_ranges(ranges)
    ranges.map do |r|
      a = r[0].to_i
      b = r[1].to_i
      a <= b ? [a, b] : [b, a]
    end
  end

  def self.in_ranges?(line, ranges)
    return true if ranges.empty?
    ranges.any? { |(s, e)| line >= s && line <= e }
  end

  def self.apply_insertions(src, inserts)
    out = src.dup.b
    kind_order = { open: 0, close: 1 }
    inserts.sort_by do |i|
      [
        -i[:pos],
        kind_order[i[:kind]],
        i[:kind] == :open ? i[:len] : -i[:len]
      ]
    end.each do |i|
      out.insert(i[:pos], i[:text].b)
    end
    out.force_encoding(src.encoding)
  end

  def self.literal_value_node?(node)
    LITERAL_NODE_CLASSES.include?(node.class)
  end

  def self.wrap_expr?(node, parent = nil)
    return false unless node.respond_to?(:location)
    return false if literal_value_node?(node)
    if parent.is_a?(Prism::AliasGlobalVariableNode) || parent.is_a?(Prism::AliasMethodNode)
      return false
    end
    if parent.is_a?(Prism::DefNode) && parent.receiver == node
      return false
    end
    if parent.is_a?(Prism::EmbeddedVariableNode)
      return false
    end
    if parent.is_a?(Prism::ImplicitNode)
      return false
    end
    if node.is_a?(Prism::ConstantReadNode) &&
       (parent.is_a?(Prism::ClassNode) || parent.is_a?(Prism::ModuleNode))
      return false
    end
    WRAP_NODE_CLASSES.include?(node.class)
  end

  def self.expr_location(node)
    loc = node.location
    return {
      start_offset: loc.start_offset,
      end_offset: loc.start_offset + loc.length,
      start_line: loc.start_line,
      start_col: loc.start_column,
      end_line: loc.end_line,
      end_col: loc.end_column
    } unless node.is_a?(Prism::CallNode)

    best = loc
    [node.arguments&.location, node.block&.location, node.closing_loc].compact.each do |l|
      next unless l
      best = l if (l.start_offset + l.length) >= (best.start_offset + best.length)
    end

    {
      start_offset: loc.start_offset,
      end_offset: best.start_offset + best.length,
      start_line: loc.start_line,
      start_col: loc.start_column,
      end_line: best.end_line,
      end_col: best.end_column
    }
  end

  def self.has_block_with_body?(call_node)
    block = call_node.child_nodes.find { |n| n.is_a?(Prism::BlockNode) }
    block && block.body.is_a?(Prism::StatementsNode)
  end

  @events_by_id = []
  @loc_by_id = []
  @next_id = 0
  @max_values_per_expr = 3

  def self.max_values_per_expr=(n)
    @max_values_per_expr = n.to_i if n && n.to_i > 0
  end

  def self.max_values_per_expr
    @max_values_per_expr
  end

  def self.events_by_id
    @events_by_id
  end

  def self.register_location(file, loc)
    @next_id += 1
    id = @next_id
    @loc_by_id[id] = {
      file: file,
      start_line: loc[:start_line],
      start_col: loc[:start_col],
      end_line: loc[:end_line],
      end_col: loc[:end_col]
    }
    id
  end

  def self.events_from_ids
    out = []
    @events_by_id.each_with_index do |e, id|
      next unless e
      loc = @loc_by_id[id]
      next unless loc
      out << {
        file: loc[:file],
        start_line: loc[:start_line],
        start_col: loc[:start_col],
        end_line: loc[:end_line],
        end_col: loc[:end_col],
        values: values_from_ring(e).map { |v| safe_value(v) },
        total: e[e.length - 1]
      }
    end
    out
  end

  def self.values_from_ring(entry)
    max = entry.length - 2
    idx = entry[max]
    total = entry[max + 1]
    len = total < max ? total : max
    return [] if len == 0

    start = idx - len
    start += max if start < 0
    out = []
    len.times do |i|
      out << entry[(start + i) % max]
    end
    out
  end

  def self.dump_json(path = nil)
    path ||= File.expand_path("lumitrace_recorded.json", Dir.pwd)
    File.write(path, JSON.dump(events_from_ids), perm: 0o600)
    path
  end

  def self.dump_events_json(events, path = nil)
    path ||= File.expand_path("lumitrace_recorded.json", Dir.pwd)
    File.write(path, JSON.dump(events), perm: 0o600)
    path
  end

  def self.load_events_json(path)
    JSON.parse(File.read(path))
  end

  def self.merge_events(events, max_values: nil)
    by_key = {}
    events.each do |e|
      file = e[:file] || e["file"]
      start_line = e[:start_line] || e["start_line"]
      start_col = e[:start_col] || e["start_col"]
      end_line = e[:end_line] || e["end_line"]
      end_col = e[:end_col] || e["end_col"]
      values = e[:values] || e["values"] || []
      total = e[:total] || e["total"] || 0

      key = [file, start_line, start_col, end_line, end_col]
      entry = (by_key[key] ||= {
        file: file,
        start_line: start_line,
        start_col: start_col,
        end_line: end_line,
        end_col: end_col,
        values: [],
        total: 0
      })

      entry[:total] += total.to_i
      entry[:values].concat(values)
      if max_values && max_values.to_i > 0 && entry[:values].length > max_values.to_i
        entry[:values] = entry[:values].last(max_values.to_i)
      end
    end
    by_key.values
  end

  def self.merge_child_events(base_events, dir, max_values: nil, logger: nil)
    return base_events unless dir && Dir.exist?(dir)
    files = Dir.glob(File.join(dir, "child_*.json"))
    return base_events if files.empty?

    logger&.call("merge: child_files=#{files.length}")
    merged = base_events.dup
    files.each do |path|
      begin
        data = load_events_json(path)
      rescue StandardError
        logger&.call("merge: skip unreadable #{path}")
        next
      end
      merged.concat(data)
      begin
        File.delete(path)
      rescue StandardError
        nil
      end
    end
    merge_events(merged, max_values: max_values)
  end

  def self.events
    events_from_ids
  end

  def self.safe_value(v)
    case v
    when Numeric, TrueClass, FalseClass, NilClass
      v
    else
      s = v.inspect
      s.bytesize > 1000 ? s[0, 1000] + "..." : s
    end
  end
end
end

if $PROGRAM_NAME == __FILE__
  path = ARGV[0] or abort "usage: ruby record_instrument.rb FILE RANGES_JSON [record_method] [out_path]"
  ranges = JSON.parse(ARGV[1] || "[]")
  record_method = ARGV[2] || "Lumitrace::R"
  out = RecordInstrument.instrument_source(File.read(path), ranges, file_label: path, record_method: record_method)

  if ARGV[3]
    File.write(ARGV[3], out)
  else
    puts out
  end
end
