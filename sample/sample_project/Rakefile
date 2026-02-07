# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb", "test/**/test_*.rb"]
  t.verbose = false
end

task default: :test
