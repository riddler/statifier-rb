# frozen_string_literal: true

require "test_helper"
require_relative "xml_helper"

# Refusals inside a tag, and the element tree's own: each with its reason,
# line and column.
class TagRefusalsTest < Minitest::Test
  include XMLHelper

  # sabotage: answer :expected_name instead of :unexpected_end at the end of
  # the source in read_name; the assert_refused for "<a></" fails.
  def test_refuses_a_document_that_ends_inside_a_tag
    assert_refused "<a", :unexpected_end, 1, 3
    assert_refused '<a x="1', :unexpected_end, 1, 8
    assert_refused "<a x", :unexpected_end, 1, 5
    assert_refused "<a x=", :unexpected_end, 1, 6
    assert_refused "<a></", :unexpected_end, 1, 6
    assert_refused "<a></a", :unexpected_end, 1, 7
  end

  # sabotage: let NAME start with a digit (add 0-9 to its first class); the
  # assert_refused for "<a><1/></a>" fails.
  def test_refuses_a_tag_with_no_name
    assert_refused "<a><1/></a>", :expected_name, 1, 5
    assert_refused "<a><!x/></a>", :expected_name, 1, 5
    assert_refused "<a\u{D7}/>", :expected_whitespace, 1, 3
  end

  # sabotage: accept a missing "=" in expect_equals (return instead of
  # refusing); the assert_refused for "<a x/>" fails.
  def test_refuses_an_attribute_with_no_equals_sign
    assert_refused "<a x/>", :expected_equals, 1, 5
  end

  # sabotage: accept an unquoted value in expect_quote (scan /["']?/); the
  # assert_refused for "<a x=1/>" fails.
  def test_refuses_an_unquoted_attribute_value
    assert_refused "<a x=1/>", :expected_quote, 1, 6
  end

  # sabotage: drop the expected_whitespace refusal in read_attributes; the
  # assert_refused fails.
  def test_refuses_attributes_with_no_whitespace_between_them
    assert_refused '<a x="1"y="2"/>', :expected_whitespace, 1, 9
  end

  # sabotage: skip any characters up to ">" in read_end_tag (skip_until(/>/)
  # in expect_tag_end); the assert_refused for "<a></a x>" fails.
  def test_refuses_an_end_tag_with_more_than_a_name
    assert_refused "<a></a x>", :expected_tag_end, 1, 8
  end

  # sabotage: drop the "<" branch from value_special and let VALUE_RUNS take
  # "<"; the assert_refused fails.
  def test_refuses_a_less_than_sign_in_an_attribute_value
    assert_refused '<a x="<"/>', :lt_in_attribute_value, 1, 7
  end

  # sabotage: accept any end tag in read_end_tag (drop the
  # `if name == open.name`); the assert_refused fails.
  def test_refuses_a_mismatched_end_tag_at_its_lt
    assert_refused "<a>\n  <b></c>\n</a>", :mismatched_end_tag, 2, 6
  end

  # sabotage: name @stack.first instead of @stack.last in refuse_unclosed;
  # the assert_includes on "<b>" fails.
  def test_refuses_an_element_left_open_naming_it
    assert_refused "<a><b>", :unclosed_element, 1, 7

    assert_includes Internals::XML.parse("<a><b>").error.message, "element <b> is never closed"
  end
end
