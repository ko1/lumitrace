require "json"
require "prism"
require_relative "./record_instrument"

module Lumitrace
module RecordRequire
  @enabled = false
  @processed = {}
  @root = File.expand_path(Dir.pwd)
  @tool_root = File.expand_path(__dir__)
  @ranges_by_file = {}
  @ranges_filtering = false

  def self.enable(max_values: nil, ranges_by_file: nil, root: nil)
    return if @enabled
    RecordInstrument.max_values_per_expr = max_values if max_values
    if root && !root.to_s.strip.empty?
      @root = File.expand_path(root.to_s)
    else
      @root = File.expand_path(ENV.fetch("LUMITRACE_ROOT", Dir.pwd))
    end
    if ranges_by_file
      @ranges_by_file = normalize_ranges_by_file(ranges_by_file)
      @ranges_filtering = true
    else
      @ranges_by_file = {}
      @ranges_filtering = false
    end
    @enabled = true
  end

  def self.ranges_for(path)
    return [] unless @ranges_filtering
    @ranges_by_file[File.expand_path(path)] || []
  end

  def self.ranges_filtering?
    @ranges_filtering
  end

  def self.listed_file?(path)
    @ranges_by_file.key?(File.expand_path(path))
  end

  def self.normalize_ranges_by_file(input)
    return {} unless input
    input.each_with_object({}) do |(file, ranges), h|
      next unless file
      abs = File.expand_path(file)
      if ranges.nil? || ranges.empty?
        h[abs] = []
      else
        h[abs] = ranges.map { |r| [r.begin, r.end] }
      end
    end
  end

  def self.disable
    @enabled = false
  end

  def self.enabled?
    @enabled
  end

  def self.in_root?(path)
    abs = File.expand_path(path)
    return true if @root == File::SEPARATOR
    abs == @root || abs.start_with?(@root + File::SEPARATOR)
  end

  def self.excluded?(path)
    abs = File.expand_path(path)
    abs.start_with?(@tool_root + File::SEPARATOR)
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
        return recordrequire_orig_translate(iseq) if respond_to?(:recordrequire_orig_translate) && !RecordRequire.enabled?
        path = iseq.path
        abs = File.expand_path(path)
        if RecordRequire.in_root?(abs) && !RecordRequire.excluded?(abs) && !RecordRequire.already_processed?(abs) &&
           (iseq.label == "<main>" || iseq.label == "<top (required)>")
          if RecordRequire.ranges_filtering? && !RecordRequire.listed_file?(abs)
            return recordrequire_orig_translate(iseq) if respond_to?(:recordrequire_orig_translate)
            return nil
          end
          RecordRequire.mark_processed(abs)
          src = File.read(abs)
          ranges = RecordRequire.ranges_for(abs)
          modified = RecordInstrument.instrument_source(src, ranges, file_label: abs)
          return RubyVM::InstructionSequence.compile(modified, abs)
        end
        return recordrequire_orig_translate(iseq) if respond_to?(:recordrequire_orig_translate)
        nil
      end
    end
  end
end

end
