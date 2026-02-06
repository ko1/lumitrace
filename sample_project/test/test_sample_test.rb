# frozen_string_literal: true

require "minitest/autorun"
require_relative "../test"

class SampleProjectTest < Minitest::Test
  def test_compute
    assert_equal 13, compute(5)
  end

  def test_foo
    assert_equal 42, 1 + 2 * 3
  end
end
