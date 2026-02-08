# frozen_string_literal: true

require "minitest/autorun"
require_relative "../test"

class SampleProjectTest < Minitest::Test
  def test_compute
    assert_equal 13, compute(5)
  end

  def test_foo
    assert_equal 42, 30 + 3 * 4
  end

  def test_bar
    assert_equal 420, (30 + 3 * 4) * 10
  end

  def test_hoge
    assert_equal 4200, (30 + 3 * 4) * 100
  end

  def test_baz
    assert_equal 43, 30 + 3 * 4 + 1
  end

end
