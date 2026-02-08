# frozen_string_literal: true

require "json"
require "tmpdir"
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
  @fork_hook_installed = false
  @fork_child = false
  @results_dir = nil
  @results_parent_pid = nil

  def self.verbose_log(message)
    return unless @verbose
    $stderr.puts("[lumitrace] #{message}")
  end

  def self.install_fork_hook
    return if @fork_hook_installed
    return unless Process.respond_to?(:_fork)
    @fork_hook_installed = true

    mod = Module.new do
      def _fork
        pid = super
        Lumitrace.after_fork_child! if pid == 0
        pid
      end
    end
    Process.singleton_class.prepend(mod)
    verbose_log("fork: Process._fork hook installed")
  end

  def self.after_fork_child!
    @fork_child = true
    return unless defined?(RecordInstrument)
    RecordInstrument.reset_events!
    verbose_log("fork: child reset events (pid=#{Process.pid})")
  end

  def self.results_parent?
    @results_parent_pid && Process.pid == @results_parent_pid
  end

  def self.results_child?
    @results_parent_pid && Process.pid != @results_parent_pid
  end

  def self.setup_results_dir
    require "fileutils"
    dir = ENV["LUMITRACE_RESULTS_DIR"]
    if dir.nil? || dir.strip.empty?
      user = ENV["USER"] || ENV["LOGNAME"] || Process.uid.to_s
      user = user.gsub(/[^A-Za-z0-9_.-]/, "_")
      dir = File.join(Dir.tmpdir, "lumitrace_results", "#{user}_#{Process.pid}")
      ENV["LUMITRACE_RESULTS_DIR"] = dir
    end
    dir = File.expand_path(dir, Dir.pwd)
    parent_pid = ENV["LUMITRACE_RESULTS_PARENT_PID"]
    if parent_pid.nil? || parent_pid.to_s.strip.empty?
      parent_pid = Process.pid.to_s
      ENV["LUMITRACE_RESULTS_PARENT_PID"] = parent_pid
    end
    @results_dir = dir
    @results_parent_pid = parent_pid.to_i
    FileUtils.mkdir_p(@results_dir, mode: 0o700)
    begin
      File.chmod(0o700, @results_dir)
    rescue StandardError
      nil
    end
    verbose_log("results_dir: #{@results_dir} parent_pid=#{@results_parent_pid}")
  end

  def self.child_results_path
    return nil unless @results_dir
    ts = format("%.6f", Time.now.to_f).tr(".", "_")
    File.join(@results_dir, "child_#{Process.pid}_#{ts}.json")
  end


  def self.serialize_ranges_by_file(ranges_by_file)
    return nil unless ranges_by_file
    specs = []
    ranges_by_file.each do |file, ranges|
      if ranges.nil? || ranges.empty?
        specs << file.to_s
        next
      end
      segs = ranges.map do |r|
        r.begin == r.end ? r.begin.to_s : "#{r.begin}-#{r.end}"
      end
      specs << "#{file}:#{segs.join(",")}"
    end
    specs.join(";")
  end

  def self.ensure_rubyopt_require
    current = ENV["RUBYOPT"].to_s
    return if current.split.any? { |t| t == "-rlumitrace" || t == "-rlumitrace/enable" }
    updated = current.strip.empty? ? "-rlumitrace" : "#{current} -rlumitrace"
    ENV["RUBYOPT"] = updated
  end

  def self.apply_exec_env(effective_text:, effective_html:, effective_json:, effective_max:, effective_root:, effective_verbose:, ranges_by_file:)
    ENV["LUMITRACE_TEXT"] = effective_text == true ? "1" : effective_text == false ? "0" : effective_text.to_s
    ENV["LUMITRACE_HTML"] = effective_html == true ? "1" : effective_html == false ? "0" : effective_html.to_s
    ENV["LUMITRACE_JSON"] = effective_json == true ? "1" : effective_json == false ? "0" : effective_json.to_s
    ENV["LUMITRACE_VALUES_MAX"] = effective_max.to_s if effective_max
    ENV["LUMITRACE_ROOT"] = effective_root.to_s if effective_root
    ENV["LUMITRACE_VERBOSE"] = effective_verbose ? "1" : "0"
    if ranges_by_file
      ENV["LUMITRACE_RANGE"] = serialize_ranges_by_file(ranges_by_file)
    end
    ENV["LUMITRACE_ENABLE"] = "1" if ENV["LUMITRACE_ENABLE"].nil?
    ensure_rubyopt_require
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

  def self.parse_cli_options(argv, banner: nil, allow_help: false, order: :permute)
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
      o.separator ""
      o.separator "Options:"
      o.on("-t", "--text[=PATH]", "Text output (stdout or PATH)") { |v| opts[:text] = v.nil? || v.empty? ? true : v }
      o.on("-h", "--html[=PATH]", "HTML output (default file or PATH)") { |v| opts[:html] = v.nil? || v.empty? ? true : v }
      o.on("-j", "--json[=PATH]", "JSON output (default file or PATH)") { |v| opts[:json] = v.nil? || v.empty? ? true : v }
      o.on("-g", "--git-diff[=MODE]", "Diff ranges (working, staged, base:REV, range:SPEC)") { |v| opts[:git_diff_mode] = v.nil? || v.empty? ? "working" : v }
      o.on("--max N", Integer, "Max values per expression") { |v| opts[:max_values] = v }
      o.on("--range SPEC", "Range: FILE:1-5,10-12 (repeatable)") { |v| opts[:range_specs] << v }
      o.on("--git-diff-context N", Integer, "Expand diff hunks by +/-N lines") { |v| opts[:git_diff_context] = v }
      o.on("--git-cmd PATH", "Git executable for diff") { |v| opts[:git_cmd] = v }
      o.on("--git-diff-no-untracked", "Exclude untracked files from diff") { opts[:git_diff_no_untracked] = true }
      o.on("--root PATH", "Root directory for instrumentation") { |v| opts[:root] = v }
      o.on("--verbose", "Verbose logs to stderr") { opts[:verbose] = true }
      if allow_help
        o.separator ""
        o.on("--help", "Show this help") { opts[:help] = true }
      end
    end

    remaining = if order == :preserve
      parser.order(argv)
    else
      parser.parse(argv)
    end
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

    if ranges_by_file.nil? && (env[:range_specs].any? || env[:git_diff_mode] || env[:git_diff_context] || env[:git_cmd] || !env[:git_diff_untracked].nil?)
      ranges_by_file = resolve_ranges_by_file(
        env[:range_specs],
        git_diff_mode: env[:git_diff_mode],
        git_diff_context: env[:git_diff_context],
        git_cmd: env[:git_cmd],
        git_diff_no_untracked: env[:git_diff_untracked] == false
      )
    end

    verbose_log("env: text=#{env[:text]} html=#{env[:html]} json=#{env[:json]} max_values=#{env[:max_values].inspect} root=#{env[:root].inspect}") if effective_verbose
    RecordRequire.enable(max_values: effective_max, ranges_by_file: ranges_by_file, root: effective_root)
    resolved_root = effective_root || Dir.pwd
    if at_exit
      setup_results_dir
      install_fork_hook
      apply_exec_env(
        effective_text: effective_text,
        effective_html: effective_html,
        effective_json: effective_json,
        effective_max: effective_max,
        effective_root: effective_root,
        effective_verbose: effective_verbose,
        ranges_by_file: ranges_by_file
      )
    end
    if ranges_by_file
      total_ranges = ranges_by_file.values.map(&:length).sum
      verbose_log("enable: text=#{effective_text} html=#{effective_html} json=#{effective_json} max_values=#{effective_max.inspect} root=#{resolved_root} ranges=#{ranges_by_file.size} total=#{total_ranges}")
      ranges_by_file.keys.sort.each do |path|
        ranges = ranges_by_file[path]
        range_text = ranges.map { |r| r.begin == r.end ? r.begin.to_s : "#{r.begin}-#{r.end}" }.join(", ")
        verbose_log("ranges: #{path}: #{range_text}")
      end
    else
      verbose_log("enable: text=#{effective_text} html=#{effective_html} json=#{effective_json} max_values=#{effective_max.inspect} root=#{resolved_root} ranges=0")
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
          if results_child?
            child_path = child_results_path
            if child_path
              RecordInstrument.dump_json(child_path)
              verbose_log("child json: #{child_path}")
            end
            next
          end

          events = RecordInstrument.events
          events = RecordInstrument.merge_child_events(
            events,
            @results_dir,
            max_values: effective_max,
            logger: method(:verbose_log)
          )

          if @atexit_json
            json_path = @atexit_json == true ? "lumitrace_recorded.json" : @atexit_json
            json_path = File.expand_path(json_path, @atexit_output_root)
            RecordInstrument.dump_events_json(events, json_path)
            verbose_log("json: #{json_path}")
          end
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
          if results_parent? && @results_dir && Dir.exist?(@results_dir)
            begin
              require "fileutils"
              FileUtils.rm_rf(@results_dir)
              verbose_log("results_dir cleanup: #{@results_dir}")
            rescue StandardError
              nil
            end
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
