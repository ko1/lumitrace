# frozen_string_literal: true

require_relative "lumitrace/version"
require_relative "lumitrace/record_instrument"
require_relative "lumitrace/generate_resulted_html"

module Lumitrace
  class Error < StandardError; end
  @atexit_registered = false
  @atexit_output_root = nil
  @atexit_ranges_by_file = nil

  def self.enable!(max_values: ENV["LUMITRACE_VALUES_MAX"], ranges_by_file: nil, at_exit: true)
    require_relative "lumitrace/record_require"
    RecordRequire.enable(max_values: max_values, ranges_by_file: ranges_by_file)
    if at_exit
      @atexit_output_root = Dir.pwd
      @atexit_ranges_by_file = ranges_by_file
      unless @atexit_registered
        at_exit do
          next unless RecordRequire.enabled?
          if ENV["LUMITRACE_JSON_OUT"] && !ENV["LUMITRACE_JSON_OUT"].empty?
            RecordInstrument.dump_json(File.expand_path(ENV["LUMITRACE_JSON_OUT"], @atexit_output_root))
          end
          events = RecordInstrument.events
          html = GenerateResultedHtml.render_all_from_events(
            events,
            root: @atexit_output_root,
            ranges_by_file: @atexit_ranges_by_file
          )
          out_path = ENV.fetch("LUMITRACE_HTML_OUT", File.expand_path("lumitrace_recorded.html", @atexit_output_root))
          File.write(out_path, html)
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
