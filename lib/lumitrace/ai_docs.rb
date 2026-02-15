# frozen_string_literal: true

module Lumitrace
  AI_DOC_GENERATED_HEADER = "<!-- generated file: do not edit. run `rake docs:ai` -->"

  def self.normalize_output_format(format)
    value = format.to_s.strip.downcase
    value = "text" if value.empty?
    unless %w[text json].include?(value)
      raise ArgumentError, "invalid format: #{format.inspect} (expected text or json)"
    end
    value
  end

  def self.render_help(format: "text")
    normalized = normalize_output_format(format)
    data = help_manifest
    return JSON.pretty_generate(data) + "\n" if normalized == "json"

    lines = []
    lines << "# Lumitrace Help"
    lines << ""
    lines << "- Version: #{data[:version]}"
    lines << "- Help version: #{data[:help_version]}"
    lines << "- Primary JSON entrypoint: `#{data[:entrypoint][:primary]}`"
    lines << "- Schema JSON entrypoint: `#{data[:entrypoint][:schema]}`"
    lines << ""
    lines << "## Recommended Flow"
    data[:recommended_flow].each { |step| lines << "- #{step}" }
    lines << ""
    lines << "## Commands"
    data[:commands].each do |cmd|
      lines << "- `#{cmd[:command]}`"
      lines << "  - #{cmd[:description]}"
    end
    lines << ""
    lines << "## Collect Modes"
    data[:collect_modes].each do |mode|
      lines << "- `#{mode[:mode]}`: #{mode[:summary]}"
    end
    lines << ""
    lines << "## Key Options"
    data[:key_options].each do |opt|
      details = []
      details << "default=#{opt[:default].inspect}" if opt.key?(:default)
      details << "values=#{opt[:values].join(',')}" if opt.key?(:values)
      details << "repeatable=true" if opt[:repeatable]
      details << opt[:note] if opt[:note]
      suffix = details.empty? ? "" : " (#{details.join('; ')})"
      lines << "- `#{opt[:name]}`#{suffix}"
    end
    lines << ""
    lines << "## Examples"
    data[:examples].each { |example| lines << "- `#{example}`" }
    lines.join("\n") + "\n"
  end

  def self.render_schema(format: "text")
    normalized = normalize_output_format(format)
    data = schema_manifest
    return JSON.pretty_generate(data) + "\n" if normalized == "json"

    lines = []
    lines << "# Lumitrace JSON Schema"
    lines << ""
    lines << "- Version: #{data[:version]}"
    lines << "- Schema version: #{data[:schema_version]}"
    lines << "- Top level: #{data[:json_top_level][:type]} of #{data[:json_top_level][:items]}"
    lines << ""
    lines << "## Common Event Fields"
    data[:event_common_fields].each do |name, spec|
      req = spec[:required] ? "required" : "optional"
      type_text = Array(spec[:type]).join("|")
      desc = spec[:description] ? " - #{spec[:description]}" : ""
      lines << "- `#{name}` (#{type_text}, #{req})#{desc}"
    end
    lines << ""
    lines << "## Value Summary Fields"
    data[:value_summary_fields].each do |name, spec|
      req = spec[:required] ? "required" : "optional"
      lines << "- `#{name}` (#{spec[:type]}, #{req})#{spec[:description] ? " - #{spec[:description]}" : ""}"
    end
    lines << ""
    lines << "## Collect Modes"
    data[:collect_modes].each do |mode|
      lines << "- `#{mode[:mode]}`"
      lines << "  - required fields: #{mode[:required_fields].join(', ')}"
      unless mode[:optional_fields].nil? || mode[:optional_fields].empty?
        lines << "  - optional fields: #{mode[:optional_fields].join(', ')}"
      end
      unless mode[:mode_fields].nil? || mode[:mode_fields].empty?
        mode[:mode_fields].each do |field, spec|
          lines << "  - `#{field}`: #{spec[:type]}#{spec[:items] ? " (items: #{spec[:items]})" : ""}"
        end
      end
    end
    lines.join("\n") + "\n"
  end

  def self.render_ai_help_markdown
    "#{AI_DOC_GENERATED_HEADER}\n\n#{render_help(format: 'text')}"
  end

  def self.render_ai_schema_markdown
    "#{AI_DOC_GENERATED_HEADER}\n\n#{render_schema(format: 'text')}"
  end
end
