# frozen_string_literal: true

require "open3"

module Lumitrace
  module GitDiff
    def self.parse_ranges(diff_text, root, context: nil)
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
            context = (context.nil? ? ENV.fetch("LUMITRACE_GIT_DIFF_CONTEXT", "3") : context).to_i
            context = 0 if context < 0
            start_line = [start_line - context, 1].max
            end_line += context
            ranges_by_file[current_file] << (start_line..end_line)
          end
        end
      end

      ranges_by_file
    end

    def self.diff_args(mode: nil)
      mode ||= ENV.fetch("LUMITRACE_GIT_DIFF", "working")
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

    def self.git_root(dir, git_cmd)
      out, status = Open3.capture2(git_cmd, "-C", dir, "rev-parse", "--show-toplevel")
      return dir unless status.success?
      out.strip
    end

    def self.untracked_files(base_dir, git_cmd, root)
      stdout, status = Open3.capture2(git_cmd, "-C", base_dir, "status", "--porcelain")
      return [] unless status.success?
      files = []
      stdout.each_line do |line|
        next unless line.start_with?("?? ")
        rel = line.sub("?? ", "").strip
        next if rel.empty?
        files << File.expand_path(rel, root)
      end
      files
    end

    def self.ranges(mode: nil, context: nil, git_cmd: nil, base_dir: nil, include_untracked: true)
      base_dir ||= Dir.pwd
      git_cmd ||= ENV.fetch("LUMITRACE_GIT_CMD", "git")
      root = git_root(base_dir, git_cmd)
      args = [git_cmd, "-C", base_dir, "diff", "--unified=0", "--no-color"] + diff_args(mode: mode)
      stdout, status = Open3.capture2(*args)
      return nil unless status.success?
      ranges_by_file = parse_ranges(stdout, root, context: context)
      if include_untracked
        untracked_files(base_dir, git_cmd, root).each do |path|
          next unless File.exist?(path)
          line_count = File.read(path).lines.length
          next if line_count == 0
          ranges_by_file[path] << (1..line_count)
        end
      end
      ranges_by_file.empty? ? nil : ranges_by_file
    end
  end
end
