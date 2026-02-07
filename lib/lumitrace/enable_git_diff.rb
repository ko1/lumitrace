# frozen_string_literal: true

require_relative "../lumitrace"
require_relative "git_diff"

module Lumitrace
  mode = ENV["LUMITRACE_GIT_DIFF"]
  context = ENV["LUMITRACE_GIT_DIFF_CONTEXT"]
  git_cmd = ENV["LUMITRACE_GIT_CMD"]
  include_untracked = ENV["LUMITRACE_GIT_DIFF_UNTRACKED"] != "0"
  ranges_by_file = GitDiff.ranges(
    mode: mode,
    context: context,
    git_cmd: git_cmd,
    include_untracked: include_untracked
  )
  if ranges_by_file
    enable!(ranges_by_file: ranges_by_file, at_exit: true)
  end
end
