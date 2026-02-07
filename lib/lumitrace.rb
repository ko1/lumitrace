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
  def self.enable!(max_values: nil, ranges_by_file: nil, root: nil, text: nil, html: nil, json: nil, verbose: nil, at_exit: true)
    require_relative "lumitrace/record_require"
    env = resolve_env_options
    return if env[:disabled]

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
