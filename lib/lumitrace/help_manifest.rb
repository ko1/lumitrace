# frozen_string_literal: true

module Lumitrace
  HELP_VERSION = 1

  def self.help_manifest
    {
      help_version: HELP_VERSION,
      tool: "lumitrace",
      version: VERSION,
      summary: "Expression-level Ruby tracer for debugging.",
      entrypoint: {
        primary: "lumitrace help --format json",
        schema: "lumitrace schema --format json"
      },
      recommended_flow: [
        "Read `lumitrace help --format json`.",
        "Read `lumitrace schema --format json` to understand output structure.",
        "Run lumitrace with `--collect-mode` and optional `--max-samples`.",
        "Inspect JSON/HTML/text outputs depending on your task."
      ],
      ai_usage_tips: [
        "First run with `--collect-mode types` to get a compact shape of runtime behavior.",
        "Then switch to `--collect-mode last` for final value inspection on suspicious lines.",
        "Use `--collect-mode history --max-samples N` only when value transitions matter.",
        "Combine `--range` or `--git-diff` to keep outputs small and focused."
      ],
      commands: [
        {
          command: "lumitrace [options] script.rb [ruby_opt]",
          description: "Run a Ruby script with Lumitrace enabled."
        },
        {
          command: "lumitrace [options] exec CMD [args...]",
          description: "Run an arbitrary command with Lumitrace env injected."
        },
        {
          command: "lumitrace help [--format text|json]",
          description: "Show AI/human help."
        },
        {
          command: "lumitrace schema [--format text|json]",
          description: "Show output schema for each collect mode."
        }
      ],
      collect_modes: COLLECT_MODES.map do |mode|
        case mode
        when "last"
          { mode: mode, summary: "Keep only the last observed value and type counts." }
        when "types"
          { mode: mode, summary: "Keep only type counts and total hit count." }
        else
          { mode: mode, summary: "Keep last N sampled values and type counts." }
        end
      end,
      key_options: [
        { name: "--collect-mode", values: COLLECT_MODES, default: "last" },
        { name: "--max-samples", type: "Integer", default: 3, note: "Used by history mode." },
        { name: "--json[=PATH]", type: "bool|string", note: "Emit JSON output." },
        { name: "--html[=PATH]", type: "bool|string", note: "Emit HTML output." },
        { name: "--text[=PATH]", type: "bool|string", note: "Emit text output." },
        { name: "--range SPEC", type: "string", repeatable: true, note: "Restrict instrumentation to file ranges." },
        { name: "--git-diff[=MODE]", type: "string", note: "Restrict instrumentation to diff hunks." }
      ],
      outputs: [
        { kind: "json", default_path: "lumitrace_recorded.json" },
        { kind: "html", default_path: "lumitrace_recorded.html" },
        { kind: "text", default_path: "stdout" }
      ],
      examples: [
        "lumitrace --collect-mode history --max-samples 5 -j app.rb",
        "lumitrace --collect-mode types -h -j app.rb",
        "lumitrace help --format json",
        "lumitrace schema --format json"
      ]
    }
  end
end
