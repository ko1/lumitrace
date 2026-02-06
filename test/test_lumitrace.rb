# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"
require_relative "../lib/lumitrace"

class LumiTraceTest < Minitest::Test
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

  def test_require_instruments_multiple_files
    skip "RubyVM::InstructionSequence unavailable" unless defined?(RubyVM::InstructionSequence)

    Dir.mktmpdir do |dir|
      ENV["LUMITRACE_ROOT"] = dir

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
  ensure
    ENV.delete("LUMITRACE_ROOT")
  end
end
