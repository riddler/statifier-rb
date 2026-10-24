# frozen_string_literal: true

require "test_helper"
require_relative "xml_helper"

# The source span on every node: 1-based lines and columns counted in code
# points, 0-based byte offsets, an exclusive end, as the reference's spans
# are (statifier-ex at the vendored tag, Statifier.Parser.Location).
class LocationsTest < Minitest::Test
  include XMLHelper

  SOURCE = %(<a>\n  <s1 id="b">\n    t\n  </s1>\n</a>)

  # sabotage: compute the column after a line feed as chunk.length -
  # newline - 1 in Cursor#count_to; the assert_equal on s1's span fails.
  def test_puts_the_line_and_column_of_its_lt_on_every_element
    a = root(SOURCE)
    s1 = element(a.children[1])

    assert_equal [[1, 1, 0, 5, 5, SOURCE.bytesize], [2, 3, 6, 4, 8, 31]], [span_of(a.location), span_of(s1.location)]
    assert_equal SOURCE, a.location.slice(SOURCE)
    assert_equal %(<s1 id="b">\n    t\n  </s1>), s1.location.slice(SOURCE)
  end

  # sabotage: take the attribute's location from the value's start
  # (@cursor.span(value_start) in read_attribute); the assert_equal on the
  # attribute's span fails.
  def test_spans_an_attribute_with_its_quotes_and_its_value_inside_them
    id = root(SOURCE).children[1].attributes.first

    assert_equal [2, 7, 10, 2, 13, 16], span_of(id.location)
    assert_equal [2, 11, 14, 2, 12, 15], span_of(id.value_location)
    assert_equal "b", id.value_location.slice(SOURCE)
  end

  # sabotage: start a text run at the read position (run_buffer using
  # @cursor.mark instead of @tag_end); the assert_equal on the run that
  # opens with a comment fails.
  def test_spans_a_text_run_from_the_end_of_one_tag_to_the_start_of_the_next
    run = root(SOURCE).children[1].children.first

    assert_equal [2, 14, 17, 4, 3, 26], span_of(run.location)
    source = "<a><!-- c -->x<!-- d --></a>"

    assert_equal "<!-- c -->x<!-- d -->", root(source).children.first.location.slice(source)
  end

  # sabotage: count bytes instead of characters for the column in
  # Cursor#count_to (chunk.bytesize); the assert_equal on b's column fails.
  def test_counts_columns_in_code_points_and_offsets_in_bytes
    b = root("<a>\u{1F4DA}\u{E9}<b/></a>").children[1]

    assert_equal [1, 6, 9], span_of(b.location).first(3)
  end

  # sabotage: let a lone CR start a line in Cursor#count_to (count "\r" as
  # well); the assert_equal on b's line fails.
  def test_starts_a_line_only_at_a_line_feed
    b = root("<a>\r<b/></a>").children[1]

    assert_equal [1, 5], span_of(b.location).first(2)
  end

  # sabotage: finish a self-closing element in open_tag with
  # @cursor.span(element.start, element.start); the assert_equal on the
  # tag's slice fails.
  def test_spans_a_self_closing_element_as_its_tag
    source = "<a> <b x='1' /> </a>"

    assert_equal "<b x='1' />", root(source).children[1].location.slice(source)
  end

  # sabotage: require "=" right after the name (drop the skip_whitespace
  # before it in expect_equals); the parse is refused and root flunks.
  def test_tolerates_whitespace_around_the_equals_sign_and_before_the_end_of_an_end_tag
    source = '<a id = "x" ></a >'
    element = root(source)

    assert_equal ["x", 'id = "x"'], [element.attributes.first.value, element.attributes.first.location.slice(source)]
    assert_equal source, element.location.slice(source)
  end
end
