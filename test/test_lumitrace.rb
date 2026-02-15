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

  def with_record_instrument_state
    mod = Lumitrace::RecordInstrument
    ivars = [:@events_by_id, :@loc_by_id, :@next_id, :@max_samples_per_expr, :@collect_mode]
    saved = ivars.each_with_object({}) { |ivar, h| h[ivar] = mod.instance_variable_get(ivar) }
    yield
  ensure
    saved.each { |ivar, value| mod.instance_variable_set(ivar, value) } if saved
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

    assert_match(/Lumitrace::R\(\d+, \(/, out)
    assert_operator out.scan(/Lumitrace::R\(\d+, \(/).length, :>=, 2
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
          "sampled_values" => ["ok"],
          "total" => 1
        }
      ]

      File.write(path, JSON.dump(events))
      File.write(sample, "puts hi\n")

      html = Lumitrace::GenerateResultedHtml.render_all(path, root: dir)
      assert_includes html, "Recorded Result View"
      assert_includes html, "sample.rb"
      assert_includes html, "Mode: history (last 1 sample)"
    end
  end

  def test_parse_cli_options_basic
    argv = ["-t", "--html=/tmp/out.html", "-j", "--max-samples", "7", "--collect-mode", "history", "--root", "/tmp/root",
            "--range", "a.rb:1-3,5-6", "--verbose", "file.rb"]
    opts, args, _parser = Lumitrace.parse_cli_options(argv, allow_help: true)

    assert_equal true, opts[:text]
    assert_equal "/tmp/out.html", opts[:html]
    assert_equal true, opts[:json]
    assert_equal 7, opts[:max_samples]
    assert_equal "history", opts[:collect_mode]
    assert_equal "/tmp/root", opts[:root]
    assert_equal ["a.rb:1-3,5-6"], opts[:range_specs]
    assert_equal 1, opts[:verbose]
    assert_equal ["file.rb"], args
  end

  def test_parse_enable_args_cli_string
    opts = Lumitrace.parse_enable_args("--text=/tmp/out.txt -h --json=/tmp/out.json --max-samples 5 --collect-mode types --root /tmp/root")

    assert_equal "/tmp/out.txt", opts[:text]
    assert_equal true, opts[:html]
    assert_equal "/tmp/out.json", opts[:json]
    assert_equal 5, opts[:max_samples]
    assert_equal "types", opts[:collect_mode]
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

  def test_merge_events_applies_max_samples
    events = [
      { file: "a.rb", start_line: 1, start_col: 0, end_line: 1, end_col: 1, sampled_values: [1, 2], total: 2 },
      { file: "a.rb", start_line: 1, start_col: 0, end_line: 1, end_col: 1, sampled_values: [3, 4], total: 2 }
    ]

    merged = Lumitrace::RecordInstrument.merge_events(events, max_samples: 3)
    assert_equal 1, merged.size
    assert_equal 4, merged[0][:total]
    assert_equal ["2", "3", "4"], merged[0][:sampled_values].map { |v| v[:preview] }
    assert_equal ["Integer", "Integer", "Integer"], merged[0][:sampled_values].map { |v| v[:type] }
    assert_equal({ "Integer" => 4 }, merged[0][:all_value_types])
    assert_nil merged[0][:sampled_value_types]
  end

  def test_events_from_ids_last_mode_outputs_last_value_and_type_set
    with_record_instrument_state do
      mod = Lumitrace::RecordInstrument
      mod.instance_variable_set(:@events_by_id, [])
      mod.instance_variable_set(:@loc_by_id, [])
      mod.instance_variable_set(:@next_id, 0)
      Lumitrace.install_collect_mode("last")
      mod.max_samples_per_expr = 3

      id = mod.register_location(
        "a.rb",
        { start_line: 1, start_col: 0, end_line: 1, end_col: 1 },
        kind: :expr
      )

      Lumitrace::R(id, 1)
      Lumitrace::R(id, nil)
      Lumitrace::R(id, "x" * 140)

      events = mod.events_from_ids
      assert_equal 1, events.length

      event = events.first
      assert_equal({ "Integer" => 1, "NilClass" => 1, "String" => 1 }, event[:all_value_types])
      assert_equal "String", event[:last_value][:type]
      assert_equal true, event[:last_value][:length] > 120
      assert_match(/\A"/, event[:last_value][:preview])
      refute event[:last_value].key?(:truncated)
      refute event[:last_value].key?(:head)
      assert_nil event[:sampled_values]
    end
  end

  def test_events_from_ids_history_mode_outputs_sampled_values
    with_record_instrument_state do
      mod = Lumitrace::RecordInstrument
      mod.instance_variable_set(:@events_by_id, [])
      mod.instance_variable_set(:@loc_by_id, [])
      mod.instance_variable_set(:@next_id, 0)
      Lumitrace.install_collect_mode("history")
      mod.max_samples_per_expr = 3

      id = mod.register_location(
        "a.rb",
        { start_line: 1, start_col: 0, end_line: 1, end_col: 1 },
        kind: :expr
      )

      Lumitrace::R(id, 1)
      Lumitrace::R(id, nil)
      Lumitrace::R(id, "x")

      events = mod.events_from_ids
      assert_equal 1, events.length
      event = events.first
      assert_equal ["1", "nil", "\"x\""], event[:sampled_values].map { |v| v[:preview] }
      assert_equal ["Integer", "NilClass", "String"], event[:sampled_values].map { |v| v[:type] }
      assert_equal({ "Integer" => 1, "NilClass" => 1, "String" => 1 }, event[:all_value_types])
      assert_nil event[:sampled_value_types]
    end
  end

  def test_text_comment_value_includes_type
    events = [
      {
        marker: true,
        kind: "expr",
        start_col: 0,
        end_col: 1,
        sampled_values: [2],
        total: 1
      }
    ]

    comment = Lumitrace::GenerateResultedHtml.comment_value_with_total_for_line(events)
    assert_equal "2 (Integer)", comment
  end

  def test_tooltip_summary_values_include_type
    summary = Lumitrace::GenerateResultedHtml.summarize_values([
      { type: "Integer", preview: "1" },
      { type: "NilClass", preview: "nil" }
    ], 2)
    assert_includes summary, "#1: 1 (Integer)"
    assert_includes summary, "#2: nil (NilClass)"
  end

  def test_tooltip_summary_uses_all_types_when_values_absent
    summary = Lumitrace::GenerateResultedHtml.summarize_values([], 2, all_types: ["MyObj", "NilClass"])
    assert_equal "types: MyObj(1), NilClass(1)", summary
  end

  def test_tooltip_summary_shows_type_counts_when_single_type_and_values_absent
    summary = Lumitrace::GenerateResultedHtml.summarize_values([], 2, all_types: ["MyObj"])
    assert_equal "types: MyObj(1)", summary
  end

  def test_render_line_uses_all_types_when_values_absent
    html = Lumitrace::GenerateResultedHtml.render_line_with_events(
      "x",
      [
        {
          key_id: "k",
          start_col: 0,
          end_col: 1,
          sampled_values: [],
          all_value_types: { "MyObj" => 2, "NilClass" => 1 },
          total: 2,
          kind: "expr",
          depth: 1
        }
      ]
    )
    assert_includes html, "types: MyObj(2), NilClass(1)"
  end

  def test_comment_value_shows_type_counts_only_when_multiple
    comment_single = Lumitrace::GenerateResultedHtml.comment_value_with_total_for_line(
      [
        {
          marker: true,
          kind: "expr",
          start_col: 0,
          end_col: 1,
          sampled_values: [{ type: "Integer", preview: "2" }],
          all_value_types: { "Integer" => 3 },
          total: 3
        }
      ]
    )
    assert_equal "2 (Integer) (3rd run)", comment_single

    comment_multi = Lumitrace::GenerateResultedHtml.comment_value_with_total_for_line(
      [
        {
          marker: true,
          kind: "expr",
          start_col: 0,
          end_col: 1,
          sampled_values: [{ type: "Integer", preview: "2" }],
          all_value_types: { "Integer" => 2, "NilClass" => 1 },
          total: 3
        }
      ]
    )
    assert_equal "2 (Integer) types: Integer(2), NilClass(1) (3rd run)", comment_multi
  end

  def test_comment_value_shows_single_type_when_values_absent
    comment = Lumitrace::GenerateResultedHtml.comment_value_with_total_for_line(
      [
        {
          marker: true,
          kind: "expr",
          start_col: 0,
          end_col: 1,
          sampled_values: [],
          all_value_types: { "Integer" => 3 },
          total: 3
        }
      ]
    )
    assert_equal "types: Integer(3) (3rd run)", comment
  end

  def test_normalize_events_keeps_sampled_value_objects
    events = [
      {
        "file" => "a.rb",
        "start_line" => 1,
        "start_col" => 0,
        "end_line" => 1,
        "end_col" => 1,
        "sampled_values" => [{ "type" => "MyObj", "preview" => "<obj>" }],
        "total" => 2
      }
    ]
    normalized = Lumitrace::GenerateResultedHtml.normalize_events(events)
    assert_equal "<obj>", normalized.first[:sampled_values].first["preview"]
  end

  def test_env_range_parsing
    with_env("LUMITRACE_RANGE" => "a.rb:1-3,5-6;b.rb", "LUMITRACE_COLLECT_MODE" => "types") do
      env = Lumitrace.resolve_env_options
      assert_equal ["a.rb:1-3,5-6", "b.rb"], env[:range_specs]
      assert_equal "types", env[:collect_mode]
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
              "require 'lumitrace'; Lumitrace.enable!(text:false,html:false,json:false); Lumitrace::R(1,1)"
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

        Lumitrace.enable!(max_samples: 3, at_exit: false)
        Lumitrace::RecordInstrument.reset_events!

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
