# frozen_string_literal: true

module Lumitrace
  def self.parse_env_flag(value)
    return nil if value.nil?
    return true if value == "1" || value.downcase == "true"
    return false if value == "0" || value.downcase == "false"
    value
  end

  def self.resolve_env_options
    html_env = parse_env_flag(ENV["LUMITRACE_HTML"])
    json_env = parse_env_flag(ENV["LUMITRACE_JSON"])
    raw_text = ENV["LUMITRACE_TEXT"]
    text_env = parse_env_flag(raw_text)
    max_env = ENV["LUMITRACE_VALUES_MAX"]
    root_env = ENV["LUMITRACE_ROOT"]

    html = html_env.nil? ? false : (html_env != false)
    html_out = html_env.is_a?(String) ? html_env : nil

    json = json_env.nil? ? false : (json_env != false ? (json_env == true ? true : json_env) : false)

    if text_env.nil?
      text = !(html || json)
    else
      text = (text_env != false)
    end

    verbose = parse_env_flag(ENV["LUMITRACE_VERBOSE"]) == true

    {
      text: text,
      text_explicit: !raw_text.nil?,
      html: html,
      html_out: html_out,
      json: json,
      max_values: max_env,
      root: root_env,
      verbose: verbose
    }
  end
end
