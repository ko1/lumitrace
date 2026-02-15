require "json"
require "prism"

module Lumitrace
  def self.R(id, value)
    raise "Lumitrace.R called before collect mode installation. Call Lumitrace.enable! first."
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
    Prism::YieldNode,
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

  def self.collect_locations_from_source(src, ranges)
    ranges = normalize_ranges(ranges || [])
    parse = Prism.parse(src)
    if parse.errors.any?
      raise "parse errors: #{parse.errors.map(&:message).join(", ") }"
    end

    locs = []
    seen_args = {}
    stack = [[parse.value, nil]]
    until stack.empty?
      node, parent = stack.pop
      next unless node

      if node.respond_to?(:location)
        line = node.location.start_line
        if in_ranges?(line, ranges) && wrap_expr?(node, parent)
          locs << expr_location(node).merge(kind: :expr)
        end
      end

      arg_locs = arg_locations_for_node(node, ranges)
      if arg_locs && !arg_locs.empty?
        arg_locs.each do |loc|
          key = [loc[:start_line], loc[:start_col], loc[:end_line], loc[:end_col], loc[:name]]
          next if seen_args[key]
          seen_args[key] = true
          locs << loc
        end
      end

      node.child_nodes.each { |child| stack << [child, node] }
    end
    locs
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

      arg_insert = arg_insert_for_node(node, ranges, file_label, record_method, src)
      inserts << arg_insert if arg_insert

      if node.respond_to?(:location)
        line = node.location.start_line
        if in_ranges?(line, ranges) && wrap_expr?(node, parent)
          loc = expr_location(node)
          id = register_location(file_label, loc, kind: :expr)
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
    kind_order = { open: 0, close: 1, arg: 2 }
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
  @max_samples_per_expr = 3
  @collect_mode = :last

  def self.max_samples_per_expr=(n)
    @max_samples_per_expr = n.to_i if n && n.to_i > 0
  end

  def self.max_samples_per_expr
    @max_samples_per_expr
  end

  def self.events_by_id
    @events_by_id
  end

  def self.collect_mode=(mode)
    @collect_mode = normalize_collect_mode(mode)
  end

  def self.collect_mode
    @collect_mode || :last
  end

  def self.normalize_collect_mode(mode)
    m = mode.to_s.strip
    m = "last" if m.empty?
    m = m.downcase
    case m
    when "last", "types", "history"
      m.to_sym
    else
      raise ArgumentError, "invalid collect mode: #{mode.inspect}"
    end
  end

  def self.reset_events!
    @events_by_id = []
  end

  def self.record_history(id, value)
    events_by_id = @events_by_id
    entry = events_by_id[id]
    if entry
      max = history_ring_size(entry)
      idx = entry[max]
      entry[idx] = value
      entry[max] = (idx + 1) % max
      entry[max + 1] += 1
      if (types = history_type_set(entry))
        type = value_type_name(value)
        types[type] = (types[type] || 0) + 1
      end
    else
      max = @max_samples_per_expr
      entry = Array.new(max + 3)
      entry[max] = max == 1 ? 0 : 1
      entry[max + 1] = 1
      entry[0] = value
      entry[max + 2] = { all_value_types: { value_type_name(value) => 1 } }
      events_by_id[id] = entry
    end
    value
  end

  def self.record_types(id, value)
    events_by_id = @events_by_id
    entry = events_by_id[id]
    if entry
      entry[:total] += 1
    else
      entry = { total: 1, all_value_types: {} }
      events_by_id[id] = entry
    end
    type = value_type_name(value)
    entry[:all_value_types][type] = (entry[:all_value_types][type] || 0) + 1
    value
  end

  def self.record_last(id, value)
    events_by_id = @events_by_id
    entry = events_by_id[id]
    if entry
      entry[:last_value] = value
      entry[:total] += 1
    else
      entry = { last_value: value, total: 1, all_value_types: {} }
      events_by_id[id] = entry
    end
    type = value_type_name(value)
    entry[:all_value_types][type] = (entry[:all_value_types][type] || 0) + 1
    value
  end

  def self.register_location(file, loc, kind: :expr, name: nil)
    @next_id += 1
    id = @next_id
    @loc_by_id[id] = {
      file: file,
      start_line: loc[:start_line],
      start_col: loc[:start_col],
      end_line: loc[:end_line],
      end_col: loc[:end_col],
      kind: kind,
      name: name
    }
    id
  end

  def self.events_from_ids
    out = []
    @events_by_id.each_with_index do |e, id|
      next unless e
      loc = @loc_by_id[id]
      next unless loc
      case collect_mode
      when :history
        raw_values = values_from_ring(e)
        all_types = history_type_set(e)
        if all_types.nil? || all_types.empty?
          all_types = {}
          raw_values.each do |v|
            t = value_type_name(v)
            all_types[t] = (all_types[t] || 0) + 1
          end
        end
        max = history_ring_size(e)
        out << {
          file: loc[:file],
          start_line: loc[:start_line],
          start_col: loc[:start_col],
          end_line: loc[:end_line],
          end_col: loc[:end_col],
          kind: loc[:kind].to_s,
          name: loc[:name],
          sampled_values: raw_values.map { |v| summarize_value(v, type: value_type_name(v)) },
          all_value_types: sorted_type_counts(all_types),
          total: e[max + 1]
        }
      when :types
        out << {
          file: loc[:file],
          start_line: loc[:start_line],
          start_col: loc[:start_col],
          end_line: loc[:end_line],
          end_col: loc[:end_col],
          kind: loc[:kind].to_s,
          name: loc[:name],
          all_value_types: sorted_type_counts(e[:all_value_types]),
          total: e[:total]
        }
      else # :last
        last_raw = e[:last_value]
        last_type = value_type_name(last_raw)
        out << {
          file: loc[:file],
          start_line: loc[:start_line],
          start_col: loc[:start_col],
          end_line: loc[:end_line],
          end_col: loc[:end_col],
          kind: loc[:kind].to_s,
          name: loc[:name],
          last_value: summarize_value(last_raw, type: last_type),
          all_value_types: sorted_type_counts(e[:all_value_types]),
          total: e[:total]
        }
      end
    end
    out
  end

  def self.values_from_ring(entry)
    max = history_ring_size(entry)
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

  def self.history_ring_size(entry)
    if entry[-1].is_a?(Hash) && entry[-1].key?(:all_value_types)
      entry.length - 3
    else
      entry.length - 2
    end
  end

  def self.history_type_set(entry)
    return nil unless entry[-1].is_a?(Hash)
    entry[-1][:all_value_types]
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

  def self.merge_events(events, max_samples: nil)
    by_key = {}
    events.each do |e|
      file = e[:file] || e["file"]
      start_line = e[:start_line] || e["start_line"]
      start_col = e[:start_col] || e["start_col"]
      end_line = e[:end_line] || e["end_line"]
      end_col = e[:end_col] || e["end_col"]
      kind = e[:kind] || e["kind"]
      name = e[:name] || e["name"]
      total = e[:total] || e["total"] || 0
      mode = if e.key?(:sampled_values) || e.key?("sampled_values")
        :history
      elsif e.key?(:last_value) || e.key?("last_value")
        :last
      else
        :types
      end
      key = [file, start_line, start_col, end_line, end_col]
      entry = (by_key[key] ||= {
        file: file,
        start_line: start_line,
        start_col: start_col,
        end_line: end_line,
        end_col: end_col,
        kind: kind,
        name: name,
        mode: mode,
        sampled_values: [],
        last_value: nil,
        all_value_types: {},
        total: 0
      })

      entry[:mode] = mode if entry[:mode] != :history && mode == :history
      entry[:total] += total.to_i

      case mode
      when :history
        values = e[:sampled_values] || e["sampled_values"] || []
        normalized_values = values.map { |v| normalize_last_value(v) }
        entry[:sampled_values].concat(normalized_values)
        all_types = normalize_type_counts(e[:all_value_types] || e["all_value_types"])
        if all_types.empty?
          normalized_values.each do |v|
            next unless v
            t = v[:type] || v["type"]
            next unless t && !t.to_s.empty?
            tt = t.to_s
            entry[:all_value_types][tt] = (entry[:all_value_types][tt] || 0) + 1
          end
        else
          all_types.each { |t, c| entry[:all_value_types][t] = (entry[:all_value_types][t] || 0) + c }
        end
        if max_samples && max_samples.to_i > 0 && entry[:sampled_values].length > max_samples.to_i
          entry[:sampled_values] = entry[:sampled_values].last(max_samples.to_i)
        end
      when :last
        all_types = normalize_type_counts(e[:all_value_types] || e["all_value_types"])
        all_types.each { |t, c| entry[:all_value_types][t] = (entry[:all_value_types][t] || 0) + c }
        entry[:last_value] = normalize_last_value(e[:last_value] || e["last_value"])
      else
        all_types = normalize_type_counts(e[:all_value_types] || e["all_value_types"])
        all_types.each { |t, c| entry[:all_value_types][t] = (entry[:all_value_types][t] || 0) + c }
      end
    end
    by_key.values.map do |entry|
      out = {
        file: entry[:file],
        start_line: entry[:start_line],
        start_col: entry[:start_col],
        end_line: entry[:end_line],
        end_col: entry[:end_col],
        kind: entry[:kind],
        name: entry[:name],
        total: entry[:total]
      }
      case entry[:mode]
      when :history
        out[:sampled_values] = entry[:sampled_values]
        out[:all_value_types] = sorted_type_counts(entry[:all_value_types])
      when :last
        out[:last_value] = entry[:last_value]
        out[:all_value_types] = sorted_type_counts(entry[:all_value_types])
      else
        out[:all_value_types] = sorted_type_counts(entry[:all_value_types])
      end
      out
    end
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

  def self.normalize_last_value(last_value)
    return nil unless last_value
    return summarize_value(last_value) unless last_value.is_a?(Hash)

    fetch = lambda do |key|
      if last_value.key?(key)
        last_value[key]
      elsif last_value.key?(key.to_s)
        last_value[key.to_s]
      end
    end

    raw_value = fetch.call(:value)
    type = fetch.call(:type)
    preview = fetch.call(:preview)
    preview = fetch.call(:inspect) if preview.nil?
    if preview.nil?
      if !raw_value.nil?
        preview = raw_value.inspect
        type ||= value_type_name(raw_value)
      else
        preview = last_value.inspect
      end
    end
    type ||= "Object"

    out = {
      type: type.to_s,
      preview: preview.to_s
    }
    length = fetch.call(:length)
    out[:length] = length.to_i if length
    out
  end

  def self.merge_child_events(base_events, dir, max_samples: nil, logger: nil)
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
    merge_events(merged, max_samples: max_samples)
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

  def self.value_type_name(v)
    name = v.class.name
    name && !name.empty? ? name : v.class.to_s
  end

  def self.summarize_value(v, type: nil)
    type ||= value_type_name(v)
    preview_limit = 120
    inspected = v.inspect
    if inspected.length > preview_limit
      {
        type: type,
        preview: "#{inspected[0, preview_limit]}...",
        length: inspected.length
      }
    else
      {
        type: type,
        preview: inspected
      }
    end
  end

  def self.definition_lines_from_source(src, ranges)
    ranges = normalize_ranges(ranges || [])
    parse = Prism.parse(src)
    if parse.errors.any?
      raise "parse errors: #{parse.errors.map(&:message).join(", ") }"
    end

    lines = {}
    stack = [parse.value]
    until stack.empty?
      node = stack.pop
      next unless node
      if node.is_a?(Prism::DefNode) && node.location
        line = node.location.start_line
        if in_ranges?(line, ranges)
          lines[line] = { endless: endless_def?(node) }
        end
      end
      node.child_nodes.each { |child| stack << child }
    end
    lines
  end

  def self.arg_locations_for_node(node, ranges)
    return [] unless node.is_a?(Prism::DefNode) || node.is_a?(Prism::BlockNode)
    return [] if endless_def?(node)
    params = parameters_for_node(node)
    return [] unless params
    arg_nodes = param_nodes_from(params)
    return [] if arg_nodes.empty?

    arg_nodes.each_with_object([]) do |pnode, out|
      next unless pnode.respond_to?(:location)
      name = param_name(pnode)
      next unless name
      loc = pnode.location
      line = loc.start_line
      next unless in_ranges?(line, ranges)
      out << {
        start_offset: loc.start_offset,
        end_offset: loc.start_offset + loc.length,
        start_line: loc.start_line,
        start_col: loc.start_column,
        end_line: loc.end_line,
        end_col: loc.end_column,
        kind: :arg,
        name: name
      }
    end
  end

  def self.arg_insert_for_node(node, ranges, file_label, record_method, src)
    return nil unless node.is_a?(Prism::DefNode) || node.is_a?(Prism::BlockNode)
    return nil if endless_def?(node)
    params = parameters_for_node(node)
    return nil unless params
    arg_nodes = param_nodes_from(params)
    return nil if arg_nodes.empty?
    body_offset = body_start_offset(node)
    used_fallback = false
    unless body_offset
      body_offset = arg_fallback_offset(node, params, src)
      used_fallback = true
    end

    records = []
    arg_nodes.each do |pnode|
      name = param_name(pnode)
      next unless name
      loc = pnode.location
      next unless loc
      line = loc.start_line
      next unless in_ranges?(line, ranges)
      id = register_location(file_label, {
        start_offset: loc.start_offset,
        end_offset: loc.start_offset + loc.length,
        start_line: loc.start_line,
        start_col: loc.start_column,
        end_line: loc.end_line,
        end_col: loc.end_column
      }, kind: :arg, name: name)
      records << "#{record_method}(#{id}, (#{name}))"
    end
    return nil if records.empty?
    prefix = used_fallback ? "; " : ""
    text = prefix + records.join("; ") + "; "
    { pos: body_offset, text: text, kind: :arg, len: 0 }
  end

  def self.arg_fallback_offset(node, params, src)
    if params.respond_to?(:location) && params.location
      pos = params.location.end_offset
      if node.is_a?(Prism::DefNode) && src
        pos += 1 if src.getbyte(pos) == ")".ord
      end
      return pos
    end
    if node.respond_to?(:opening_loc) && node.opening_loc
      return node.opening_loc.end_offset
    end
    nil
  end

  def self.endless_def?(node)
    return false unless node.is_a?(Prism::DefNode)
    node.respond_to?(:equal_loc) && node.equal_loc
  end

  def self.parameters_for_node(node)
    return node.parameters if node.is_a?(Prism::DefNode) || node.is_a?(Prism::BlockNode)
    nil
  end

  def self.body_start_offset(node)
    body = if node.respond_to?(:body)
      node.body
    else
      nil
    end
    return nil unless body && body.respond_to?(:location)
    if body.respond_to?(:statements) && body.statements&.body&.first&.location
      body.statements.body.first.location.start_offset
    else
      body.location.start_offset
    end
  end

  def self.param_nodes_from(params)
    nodes = []
    params.child_nodes.each do |child|
      nodes.concat(extract_param_nodes(child))
    end
    nodes
  end

  def self.extract_param_nodes(node)
    return [] unless node
    if node.respond_to?(:name)
      return [node]
    end
    if node.respond_to?(:parameters)
      return extract_param_nodes(node.parameters)
    end
    if node.respond_to?(:requireds)
      nodes = []
      nodes.concat(node.requireds) if node.requireds
      nodes.concat(node.optionals) if node.respond_to?(:optionals) && node.optionals
      nodes << node.rest if node.respond_to?(:rest) && node.rest
      nodes.concat(node.posts) if node.respond_to?(:posts) && node.posts
      nodes.concat(node.keywords) if node.respond_to?(:keywords) && node.keywords
      nodes << node.keyword_rest if node.respond_to?(:keyword_rest) && node.keyword_rest
      nodes << node.block if node.respond_to?(:block) && node.block
      return nodes.flat_map { |n| extract_param_nodes(n) }
    end
    if node.respond_to?(:target)
      return extract_param_nodes(node.target)
    end
    if node.respond_to?(:targets)
      return node.targets.flat_map { |t| extract_param_nodes(t) }
    end
    []
  end

  def self.param_name(node)
    return nil unless node.respond_to?(:name)
    name = node.name
    return nil if name.nil? || name == ""
    name.to_s
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
