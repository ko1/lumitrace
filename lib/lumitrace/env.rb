# frozen_string_literal: true

module Lumitrace
  def self.parse_env_flag(value)
    return nil if value.nil?
    return true if value == "1" || value.downcase == "true"
    return false if value == "0" || value.downcase == "false"
    value
  end

  def self.parse_env_int(value)
    return nil if value.nil?
    flag = parse_env_flag(value)
    return 1 if flag == true
    return 0 if flag == false
    flag.to_i
  end

  def self.resolve_env_options
    html_env = parse_env_flag(ENV["LUMITRACE_HTML"])
    json_env = parse_env_flag(ENV["LUMITRACE_JSON"])
    raw_text = ENV["LUMITRACE_TEXT"]
    text_env = parse_env_flag(raw_text)
    range_env = ENV["LUMITRACE_RANGE"]
    git_diff_env = ENV["LUMITRACE_GIT_DIFF"]
    git_diff_context_env = ENV["LUMITRACE_GIT_DIFF_CONTEXT"]
    git_cmd_env = ENV["LUMITRACE_GIT_CMD"]
    git_diff_untracked_env = parse_env_flag(ENV["LUMITRACE_GIT_DIFF_UNTRACKED"])
    max_env = ENV["LUMITRACE_MAX_SAMPLES"]
    root_env = ENV["LUMITRACE_ROOT"]
    collect_mode_env = ENV["LUMITRACE_COLLECT_MODE"]

    html = html_env.nil? ? false : (html_env != false)
    html_out = html_env.is_a?(String) ? html_env : nil

    json = json_env.nil? ? false : (json_env != false ? (json_env == true ? true : json_env) : false)

    if text_env.nil?
      text = !(html || json)
    else
      text = (text_env != false)
    end

    verbose = parse_env_int(ENV["LUMITRACE_VERBOSE"])
    range_specs = if range_env.nil? || range_env.strip.empty?
      []
    else
      range_env.split(";").map(&:strip).reject(&:empty?)
    end
    git_diff_context = git_diff_context_env ? git_diff_context_env.to_i : nil
    git_diff_untracked = git_diff_untracked_env.nil? ? nil : (git_diff_untracked_env != false)

    {
      text: text,
      text_explicit: !raw_text.nil?,
      html: html,
      html_out: html_out,
      json: json,
      range_specs: range_specs,
      git_diff_mode: git_diff_env,
      git_diff_context: git_diff_context,
      git_cmd: git_cmd_env,
      git_diff_untracked: git_diff_untracked,
      max_samples: max_env,
      root: root_env,
      collect_mode: collect_mode_env,
      verbose: verbose
    }
  end
end
