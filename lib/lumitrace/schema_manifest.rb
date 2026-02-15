# frozen_string_literal: true

module Lumitrace
  SCHEMA_VERSION = 1

  def self.schema_manifest
    {
      schema_version: SCHEMA_VERSION,
      tool: "lumitrace",
      version: VERSION,
      json_top_level: {
        type: "array",
        items: "event"
      },
      event_common_fields: {
        file: { type: "string", required: true, description: "Absolute source path." },
        start_line: { type: "integer", required: true },
        start_col: { type: "integer", required: true },
        end_line: { type: "integer", required: true },
        end_col: { type: "integer", required: true },
        kind: { type: "string", required: true, enum: %w[expr arg] },
        name: { type: ["string", "null"], required: false, description: "Present for kind=arg." },
        total: { type: "integer", required: true, description: "Execution count." },
        types: {
          type: "object",
          required: true,
          additional_properties: "integer",
          description: "Ruby class name => observed count."
        }
      },
      value_summary_fields: {
        type: { type: "string", required: true, description: "Ruby class name." },
        preview: { type: "string", required: true, description: "Value preview string (inspect-based)." },
        length: { type: "integer", required: false, description: "Original preview length when preview was truncated." }
      },
      collect_modes: [
        {
          mode: "last",
          required_fields: %w[file start_line start_col end_line end_col kind total types last_value],
          optional_fields: %w[name],
          mode_fields: {
            last_value: { type: "value_summary", required: true }
          }
        },
        {
          mode: "types",
          required_fields: %w[file start_line start_col end_line end_col kind total types],
          optional_fields: %w[name],
          mode_fields: {}
        },
        {
          mode: "history",
          required_fields: %w[file start_line start_col end_line end_col kind total types sampled_values],
          optional_fields: %w[name],
          mode_fields: {
            sampled_values: { type: "array", items: "value_summary", required: true }
          }
        }
      ]
    }
  end
end
