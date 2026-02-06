# frozen_string_literal: true

require_relative "lumitrace/version"
require_relative "lumitrace/record_instrument"
require_relative "lumitrace/record_require"
require_relative "lumitrace/generate_resulted_html"

module Lumitrace
  class Error < StandardError; end
end
