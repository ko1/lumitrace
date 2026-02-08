# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"
require "rbconfig"
require_relative "../lib/lumitrace"

class LumiTraceTest < Minitest::Test
  def reset_record_require
    return unless defined?(Lumitrace::RecordRequire)
    Lumitrace::RecordRequire.instance_variable_set(:@enabled, false)
    Lumitrace::RecordRequire.instance_variable_set(:@processed, {})
    Lumitrace::RecordRequire.instance_variable_set(:@ranges_by_file, {})
    Lumitrace::RecordRequire.instance_variable_set(:@ranges_filtering, false)
  end

  def with_env(overrides)
    previous = {}
    overrides.each do |k, v|
      previous[k] = ENV.key?(k) ? ENV[k] : :__unset__
      if v.nil?
        ENV.delete(k)
      else
        ENV[k] = v
      end
    end
    yield
  ensure
    previous.each do |k, v|
      if v == :__unset__
        ENV.delete(k)
      else
        ENV[k] = v
      end
    end
  end
  def test_namespaces_loaded
    assert defined?(Lumitrace::RecordInstrument)
    assert defined?(Lumitrace::GenerateResultedHtml)
  end

  def test_instrument_wraps_calls_and_reads
    src = <<~RUBY
      def compute(x)
        v1 = add(x, 2)
        v2 = mul(v1, 3)
      end
    RUBY

    out = Lumitrace::RecordInstrument.instrument_source(src, [], file_label: "sample.rb")

    assert_includes out, "Lumitrace::RecordInstrument.expr_record(\"sample.rb\", 2, 7,"
    assert_includes out, "Lumitrace::RecordInstrument.expr_record(\"sample.rb\", 2, 11,"
  end

  def test_render_all_generates_html
    Dir.mktmpdir do |dir|
      path = File.join(dir, "lumitrace_events.json")
      sample = File.join(dir, "sample.rb")
      events = [
        {
          "file" => sample,
          "start_line" => 1,
          "start_col" => 0,
          "end_line" => 1,
          "end_col" => 5,
          "values" => ["ok"],
          "total" => 1
        }
      ]

      File.write(path, JSON.dump(events))
      File.write(sample, "puts hi\n")

      html = Lumitrace::GenerateResultedHtml.render_all(path, root: dir)
      assert_includes html, "Recorded Result View"
      assert_includes html, "sample.rb"
    end
  end

  def test_parse_cli_options_basic
    argv = ["-t", "--html=/tmp/out.html", "-j", "--max", "7", "--root", "/tmp/root",
            "--range", "a.rb:1-3,5-6", "--verbose", "file.rb"]
    opts, args, _parser = Lumitrace.parse_cli_options(argv, allow_help: true)

    assert_equal true, opts[:text]
    assert_equal "/tmp/out.html", opts[:html]
    assert_equal true, opts[:json]
    assert_equal 7, opts[:max_values]
    assert_equal "/tmp/root", opts[:root]
    assert_equal ["a.rb:1-3,5-6"], opts[:range_specs]
    assert_equal true, opts[:verbose]
    assert_equal ["file.rb"], args
  end

  def test_parse_enable_args_cli_string
    opts = Lumitrace.parse_enable_args("--text=/tmp/out.txt -h --json=/tmp/out.json --max 5 --root /tmp/root")

    assert_equal "/tmp/out.txt", opts[:text]
    assert_equal true, opts[:html]
    assert_equal "/tmp/out.json", opts[:json]
    assert_equal 5, opts[:max_values]
    assert_equal File.expand_path("/tmp/root"), opts[:root]
  end

  def test_resolve_ranges_by_file_from_specs
    ranges = Lumitrace.resolve_ranges_by_file(
      ["a.rb:1-3,5-6", "b.rb"],
      git_diff_mode: nil,
      git_diff_context: nil,
      git_cmd: nil,
      git_diff_no_untracked: false
    )

    assert_equal [1..3, 5..6], ranges[File.expand_path("a.rb")]
    assert_equal [], ranges[File.expand_path("b.rb")]
  end

  def test_results_dir_defaults_to_tmpdir
    Dir.mktmpdir do |dir|
      with_env(
        "LUMITRACE_RESULTS_DIR" => nil,
        "LUMITRACE_RESULTS_PARENT_PID" => nil
      ) do
        Dir.chdir(dir) do
          Lumitrace.setup_results_dir
          assert_includes ENV["LUMITRACE_RESULTS_DIR"], Dir.tmpdir
          assert_equal Process.pid, ENV["LUMITRACE_RESULTS_PARENT_PID"].to_i
        end
      end
    end
  end

  def test_merge_events_applies_max_values
    events = [
      { file: "a.rb", start_line: 1, start_col: 0, end_line: 1, end_col: 1, values: [1, 2], total: 2 },
      { file: "a.rb", start_line: 1, start_col: 0, end_line: 1, end_col: 1, values: [3, 4], total: 2 }
    ]

    merged = Lumitrace::RecordInstrument.merge_events(events, max_values: 3)
    assert_equal 1, merged.size
    assert_equal 4, merged[0][:total]
    assert_equal [2, 3, 4], merged[0][:values]
  end

  def test_env_range_parsing
    with_env("LUMITRACE_RANGE" => "a.rb:1-3,5-6;b.rb") do
      env = Lumitrace.resolve_env_options
      assert_equal ["a.rb:1-3,5-6", "b.rb"], env[:range_specs]
    end
  end

  def test_exec_merges_to_results_dir
    skip "fork not supported" unless Process.respond_to?(:fork)
    Dir.mktmpdir do |dir|
      with_env(
        "LUMITRACE_RESULTS_DIR" => nil,
        "LUMITRACE_RESULTS_PARENT_PID" => nil
      ) do
        Dir.chdir(dir) do
          reset_record_require
          Lumitrace.enable!(text: false, html: false, json: false, at_exit: false)
          Lumitrace.setup_results_dir
          parent_dir = ENV["LUMITRACE_RESULTS_DIR"]
          assert parent_dir && !parent_dir.empty?

          pid = Process.fork do
            env = {
              "RUBYLIB" => [File.expand_path("../lib", __dir__), ENV["RUBYLIB"]].compact.join(":")
            }
            exec(
              env,
              RbConfig.ruby,
              "-e",
              "require 'lumitrace'; Lumitrace.enable!(text:false,html:false,json:false); Lumitrace::RecordInstrument.expr_record('x.rb',1,0,1,1,1)"
            )
          end
          Process.wait(pid)

          files = Dir.glob(File.join(parent_dir, "child_*.json"))
          assert files.any?, "expected child json under #{parent_dir}"
        end
      end
    end
  end

  def test_require_instruments_multiple_files
    skip "RubyVM::InstructionSequence unavailable" unless defined?(RubyVM::InstructionSequence)

    Dir.mktmpdir do |dir|
      with_env(
        "LUMITRACE_RANGE" => nil,
        "LUMITRACE_GIT_DIFF" => nil,
        "LUMITRACE_GIT_DIFF_CONTEXT" => nil,
        "LUMITRACE_GIT_CMD" => nil,
        "LUMITRACE_GIT_DIFF_UNTRACKED" => nil,
        "LUMITRACE_TEXT" => nil,
        "LUMITRACE_HTML" => nil,
        "LUMITRACE_JSON" => nil,
        "LUMITRACE_ROOT" => dir
      ) do
        reset_record_require
        main = File.join(dir, "main.rb")
        sub = File.join(dir, "sub.rb")

        File.write(sub, <<~RUBY)
          def sub_value(x)
            x + 1
          end
        RUBY

        File.write(main, <<~RUBY)
          require_relative "./sub"
          sub_value(10)
        RUBY

        Lumitrace.enable!(max_values: 3, at_exit: false)
        Lumitrace::RecordInstrument.instance_variable_set(:@events_by_key, {})

        load main

        out = File.join(dir, "events.json")
        Lumitrace::RecordInstrument.dump_json(out)
        events = JSON.parse(File.read(out))
        files = events.map { |e| e["file"] }.uniq

        assert_includes files, main
        assert_includes files, sub
      end
    end
  end

  def test_instrument_stdlib_compiles
    skip "RubyVM::InstructionSequence unavailable" unless defined?(RubyVM::InstructionSequence)

    rubylibdir = RbConfig::CONFIG["rubylibdir"]
    rubyarchdir = RbConfig::CONFIG["rubyarchdir"]
    dirs = [rubylibdir, rubyarchdir].compact.uniq
    files = dirs.flat_map { |d| Dir.glob(File.join(d, "**", "*.rb")) }
    files = files.reject { |f| f.include?("/site_ruby/") || f.include?("/vendor_ruby/") }
    files = files.uniq.sort

    assert files.any?, "no stdlib .rb files found under #{dirs.join(", ")}"

    files.each do |path|
      src = File.read(path)
      begin
        modified = Lumitrace::RecordInstrument.instrument_source(src, [], file_label: path)
      rescue StandardError => e
        flunk "instrument failed for #{path}: #{e.class}: #{e.message}"
      end

      assert modified.is_a?(String), "instrument did not return string for #{path}"

      begin
        RubyVM::InstructionSequence.compile(modified, path)
      rescue SyntaxError => e
        flunk "compile failed for #{path}: #{e.message}"
      end

      assert true, "compile succeeded for #{path}"
    end
  end
end
