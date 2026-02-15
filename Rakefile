# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb", "test/**/test_*.rb"]
  t.verbose = false
end

task default: :test

require "benchmark"

desc "Sync embedded Lumitrace code in runv/index.html"
task :runv do
  ruby "runv/sync_inline.rb"
end

desc "Run simple runtime comparison for lumitrace vs ruby"
task :bench do
  sample = File.expand_path("bench/bench_sample.rb", __dir__)
  unless File.exist?(sample)
    abort "missing bench/bench_sample.rb"
  end

  env = {}
  env["N"] = ENV["N"] if ENV["N"]

  def run_cmd(label, env, cmd)
    t = Benchmark.realtime do
      ok = system(env, *cmd, out: File::NULL, err: File::NULL)
      raise "failed: #{cmd.join(' ')}" unless ok
    end
    puts format("%-12s %8.3fs", label, t)
  end

  puts "N=#{env['N'] || 1000}"
  run_cmd("ruby", env, ["ruby", sample])
  run_cmd("lumitrace", env, ["./exe/lumitrace", sample])
end
