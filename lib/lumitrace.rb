# frozen_string_literal: true

require_relative "lumitrace/version"
require_relative "lumitrace/record_instrument"
require_relative "lumitrace/generate_resulted_html"
require_relative "lumitrace/env"

module Lumitrace
  class Error < StandardError; end
  @atexit_registered = false
  @atexit_output_root = nil
  @atexit_ranges_by_file = nil
  @verbose = false

  def self.verbose_log(message)
    return unless @verbose
    $stderr.puts("[lumitrace] #{message}")
  end

  def self.parse_range_specs(range_specs)
    return nil if range_specs.empty?
    ranges_by_file = Hash.new { |h, k| h[k] = [] }
    range_specs.each do |spec|
      file_part, range_part = spec.split(":", 2)
      if file_part.nil? || file_part.strip.empty?
        raise ArgumentError, "invalid --range (expected FILE or FILE:1-5,10-12): #{spec}"
      end

      file = File.expand_path(file_part)
      if range_part.nil? || range_part.strip.empty?
        ranges_by_file[file] = []
        next
      end

      range_part.split(",").each do |seg|
        seg = seg.strip
        if seg =~ /\A(\d+)-(\d+)\z/
          ranges_by_file[file] << ($1.to_i..$2.to_i)
        else
          raise ArgumentError, "invalid --range segment (expected N-M): #{seg}"
        end
      end
    end
    ranges_by_file
  end

  def self.parse_cli_options(argv, banner: nil, allow_help: false)
    require "optparse"

    opts = {
      text: nil,
      html: nil,
      json: nil,
      verbose: nil,
      max_values: nil,
      root: nil,
      range_specs: [],
      git_diff_mode: nil,
      git_diff_context: nil,
      git_cmd: nil,
      git_diff_no_untracked: false,
      help: false
    }

    parser = OptionParser.new do |o|
      o.banner = banner if banner
      o.on("--root PATH") { |v| opts[:root] = v }
      o.on("--text [PATH]") { |v| opts[:text] = v && !v.empty? ? v : true }
      o.on("--html [PATH]") { |v| opts[:html] = v && !v.empty? ? v : true }
      o.on("--json [PATH]") { |v| opts[:json] = v.nil? || v.empty? ? true : v }
      o.on("--max N", Integer) { |v| opts[:max_values] = v }
      o.on("--range SPEC") { |v| opts[:range_specs] << v }
      o.on("--git-diff [MODE]") { |v| opts[:git_diff_mode] = v || "working" }
      o.on("--git-diff-context N", Integer) { |v| opts[:git_diff_context] = v }
      o.on("--git-cmd PATH") { |v| opts[:git_cmd] = v }
      o.on("--git-diff-no-untracked") { opts[:git_diff_no_untracked] = true }
      o.on("--verbose") { opts[:verbose] = true }
      if allow_help
        o.on("-h", "--help") { opts[:help] = true }
      end
    end

    remaining = parser.parse(argv)
    [opts, remaining, parser]
  end

  def self.resolve_ranges_by_file(range_specs, git_diff_mode:, git_diff_context:, git_cmd:, git_diff_no_untracked:)
    ranges_by_file = parse_range_specs(range_specs) if range_specs.any?

    if git_diff_mode || git_diff_context || git_cmd || git_diff_no_untracked
      require_relative "lumitrace/git_diff"
      diff_ranges = GitDiff.ranges(
        mode: git_diff_mode,
        context: git_diff_context,
        git_cmd: git_cmd,
        include_untracked: !git_diff_no_untracked
      )
      if diff_ranges
        if ranges_by_file
          diff_ranges.each { |file, ranges| ranges_by_file[file].concat(ranges) }
        else
          ranges_by_file = diff_ranges
        end
      end
    end

    ranges_by_file
  end

  def self.parse_enable_args(arg_string)
    require "shellwords"
    argv = Shellwords.split(arg_string)
    opts, _remaining, _parser = parse_cli_options(argv)
    opts[:root] = File.expand_path(opts[:root]) if opts[:root] && !opts[:root].strip.empty?
    opts[:ranges_by_file] = resolve_ranges_by_file(
      opts[:range_specs],
      git_diff_mode: opts[:git_diff_mode],
      git_diff_context: opts[:git_diff_context],
      git_cmd: opts[:git_cmd],
      git_diff_no_untracked: opts[:git_diff_no_untracked]
    )
    opts
  end
  def self.enable!(max_values: nil, ranges_by_file: nil, root: nil, text: nil, html: nil, json: nil, verbose: nil, at_exit: true)
    require_relative "lumitrace/record_require"
    env = resolve_env_options

    effective_html = if html.nil?
      env[:html] ? (env[:html_out] || true) : false
    else
      html
    end
    effective_json = json.nil? ? env[:json] : json

    effective_text = if text.nil?
      if env[:text_explicit]
        env[:text]
      else
        !(effective_html || effective_json)
      end
    else
      text
    end

    effective_max = max_values.nil? ? env[:max_values] : max_values
    effective_root = root.nil? ? env[:root] : root
    effective_verbose = verbose.nil? ? env[:verbose] : verbose

    @verbose = effective_verbose
    if (effective_max.nil? || (effective_max.respond_to?(:empty?) && effective_max.empty?)) && effective_text
      effective_max = 1
    end

    verbose_log("env: text=#{env[:text]} html=#{env[:html]} json=#{env[:json]} max_values=#{env[:max_values].inspect} root=#{env[:root].inspect}") if effective_verbose
    RecordRequire.enable(max_values: effective_max, ranges_by_file: ranges_by_file, root: effective_root)
    if ranges_by_file
      total_ranges = ranges_by_file.values.map(&:length).sum
      verbose_log("enable: text=#{effective_text} html=#{effective_html} json=#{effective_json} max_values=#{effective_max.inspect} root=#{effective_root.inspect} ranges=#{ranges_by_file.size} total=#{total_ranges}")
      ranges_by_file.keys.sort.each do |path|
        ranges = ranges_by_file[path]
        range_text = ranges.map { |r| r.begin == r.end ? r.begin.to_s : "#{r.begin}-#{r.end}" }.join(", ")
        verbose_log("ranges: #{path}: #{range_text}")
      end
    else
      verbose_log("enable: text=#{effective_text} html=#{effective_html} json=#{effective_json} max_values=#{effective_max.inspect} root=#{effective_root.inspect} ranges=0")
    end
    if at_exit
      @atexit_output_root = Dir.pwd
      @atexit_ranges_by_file = ranges_by_file
      @atexit_text = effective_text
      @atexit_html = effective_html
      @atexit_json = effective_json
      unless @atexit_registered
        at_exit do
          next unless RecordRequire.enabled?
          if @atexit_json
            json_path = @atexit_json == true ? "lumitrace_recorded.json" : @atexit_json
            json_path = File.expand_path(json_path, @atexit_output_root)
            RecordInstrument.dump_json(json_path)
            verbose_log("json: #{json_path}")
          end
          events = RecordInstrument.events
          if @atexit_text
            text = GenerateResultedHtml.render_text_all_from_events(
              events,
              root: @atexit_output_root,
              ranges_by_file: @atexit_ranges_by_file
            )
            if @atexit_text == true
              puts text
              verbose_log("text: printed #{text.lines.count} lines")
            else
              text_path = File.expand_path(@atexit_text, @atexit_output_root)
              File.write(text_path, text)
              verbose_log("text: #{text_path}")
            end
          end
          if @atexit_html
            html = GenerateResultedHtml.render_all_from_events(
              events,
              root: @atexit_output_root,
              ranges_by_file: @atexit_ranges_by_file
            )
            out_path = @atexit_html == true ? "lumitrace_recorded.html" : @atexit_html
            out_path = File.expand_path(out_path, @atexit_output_root)
            File.write(out_path, html)
            verbose_log("html: #{out_path}")
          end
        end
        @atexit_registered = true
      end
    end
  end

  def self.disable!
    return unless defined?(RecordRequire)
    RecordRequire.disable
  end

end

enable_env = Lumitrace.parse_env_flag(ENV["LUMITRACE_ENABLE"])
if enable_env == true
  Lumitrace.enable!
elsif enable_env.is_a?(String)
  opts = Lumitrace.parse_enable_args(enable_env)
  Lumitrace.enable!(
    max_values: opts[:max_values],
    ranges_by_file: opts[:ranges_by_file],
    root: opts[:root],
    text: opts[:text],
    html: opts[:html],
    json: opts[:json],
    verbose: opts[:verbose]
  )
end
