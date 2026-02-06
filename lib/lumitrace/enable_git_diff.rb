# frozen_string_literal: true

require "open3"
require_relative "../lumitrace"

def lumitrace_parse_git_diff_ranges(diff_text, root)
  ranges_by_file = Hash.new { |h, k| h[k] = [] }
  current_file = nil

  diff_text.each_line do |line|
    if line.start_with?("+++ ")
      path = line.sub("+++ ", "").strip
      if path == "/dev/null"
        current_file = nil
      else
        path = path.sub(%r{\A[ab]/}, "")
        current_file = File.expand_path(path, root)
      end
    elsif line.start_with?("@@")
      next unless current_file
      if line =~ /\+(\d+)(?:,(\d+))?\s@@/
        start_line = Regexp.last_match(1).to_i
        count = Regexp.last_match(2) ? Regexp.last_match(2).to_i : 1
        next if count == 0
        end_line = start_line + count - 1
        context = ENV.fetch("LUMITRACE_GIT_DIFF_CONTEXT", "3").to_i
        context = 0 if context < 0
        start_line = [start_line - context, 1].max
        end_line += context
        ranges_by_file[current_file] << (start_line..end_line)
      end
    end
  end

  ranges_by_file
end

def lumitrace_diff_args
  mode = ENV.fetch("LUMITRACE_GIT_DIFF", "working")
  case mode
  when "working"
    []
  when "staged"
    ["--cached"]
  when /\Abase:(.+)\z/
    [Regexp.last_match(1)]
  when /\Arange:(.+)\z/
    [Regexp.last_match(1)]
  else
    abort "invalid LUMITRACE_GIT_DIFF (working|staged|base:REV|range:SPEC): #{mode}"
  end
end

def lumitrace_git_root(dir, git_cmd)
  out, status = Open3.capture2(git_cmd, "-C", dir, "rev-parse", "--show-toplevel")
  return dir unless status.success?
  out.strip
end

def lumitrace_diff_ranges
  base_dir = Dir.pwd
  git_cmd = ENV.fetch("LUMITRACE_GIT_CMD", "git")
  root = lumitrace_git_root(base_dir, git_cmd)
  args = [git_cmd, "-C", base_dir, "diff", "--unified=0", "--no-color"] + lumitrace_diff_args
  stdout, status = Open3.capture2(*args)
  return nil unless status.success?
  ranges_by_file = lumitrace_parse_git_diff_ranges(stdout, root)
  ranges_by_file.empty? ? nil : ranges_by_file
end

ranges_by_file = lumitrace_diff_ranges
Lumitrace.enable!(ranges_by_file: ranges_by_file, at_exit: true) if ranges_by_file
