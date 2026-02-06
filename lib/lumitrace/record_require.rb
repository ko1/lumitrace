require "json"
require "prism"
require_relative "./record_instrument"

module Lumitrace
module RecordRequire
  @enabled = false
  @processed = {}
  @root = File.expand_path(ENV.fetch("LUMITRACE_ROOT", Dir.pwd))
  @tool_root = File.expand_path(__dir__)
  @tool_files = %w[
    record_instrument.rb
    record_require.rb
    generate_resulted_html.rb
  ].map { |f| File.expand_path(f, @tool_root) }.to_h { |p| [p, true] }
  @tool_files[File.expand_path("../../exe/lumitrace", __dir__)] = true

  def self.enable(max_values: nil)
    return if @enabled
    RecordInstrument.max_values_per_expr = max_values if max_values
    @enabled = true
  end

  def self.in_root?(path)
    abs = File.expand_path(path)
    abs.start_with?(@root + File::SEPARATOR)
  end

  def self.excluded?(path)
    abs = File.expand_path(path)
    @tool_files[abs]
  end

  def self.already_processed?(path)
    @processed[path]
  end

  def self.mark_processed(path)
    @processed[path] = true
  end
end

if defined?(RubyVM::InstructionSequence)
  class RubyVM::InstructionSequence
    class << self
      if respond_to?(:translate)
        alias_method :recordrequire_orig_translate, :translate
      end

      def translate(iseq)
        path = iseq.path
        if RecordRequire.in_root?(path) && !RecordRequire.excluded?(path) && !RecordRequire.already_processed?(path) &&
           (iseq.label == "<main>" || iseq.label == "<top (required)>")
          RecordRequire.mark_processed(path)
          src = File.read(path)
          modified = RecordInstrument.instrument_source(src, [], file_label: path)
          return RubyVM::InstructionSequence.compile(modified, path)
        end
        return recordrequire_orig_translate(iseq) if respond_to?(:recordrequire_orig_translate)
        nil
      end
    end
  end
end

at_exit do
  RecordInstrument.dump_json
end
end
