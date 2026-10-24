# frozen_string_literal: true

module XMLHelper
  SCXML = "http://www.w3.org/2005/07/scxml"

  # The root element of source, failing the test when it is refused.
  def root(source)
    result = parse(source)
    flunk "expected a parse, got #{result.error.message}" unless result.ok?
    result.value
  end

  def element(node)
    assert_kind_of Statifier::XML::Element, node
    node
  end

  def text(node)
    assert_kind_of Statifier::XML::Text, node
    node
  end

  def attribute_value(source) = root(source).attributes.first.value

  def text_value(source) = text(root(source).children.first).value

  # The line, column and byte offset a span starts at, then where it ends.
  def span_of(location)
    [location.start_line, location.start_column, location.start_offset,
     location.end_line, location.end_column, location.end_offset]
  end

  # The result of parsing source, failing the test, rather than erroring it,
  # when the parse raises.
  def parse(source)
    Statifier::XML.parse(source)
  rescue StandardError => e
    flunk "#{source.inspect} raised #{e.class}: #{e.message}"
  end

  # Asserts that source is refused for reason at line and column, with a
  # zero-width location and a message that names the position.
  def assert_refused(source, reason, line, column)
    error = refusal(source)

    assert_equal [reason, line, column], [error.reason, *start_of(error)], source.inspect
    assert_equal error.location.start_offset, error.location.end_offset
    assert_includes error.message, "(line #{line}, column #{column})"
  end

  # The error source is refused with, failing the test when it is read.
  def refusal(source)
    result = parse(source)

    refute_predicate result, :ok?, "expected #{source.inspect} to be refused"
    assert_nil result.value
    result.error
  end

  # The line and column a node or an error starts at.
  def start_of(node) = [node.location.start_line, node.location.start_column]

  # The node reached from node by each child index in turn.
  def descend(node, *indexes) = indexes.reduce(node) { |parent, index| parent.children.fetch(index) }
end
