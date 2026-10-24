# frozen_string_literal: true

module LoweringHelper
  SCXML = "http://www.w3.org/2005/07/scxml"

  # The result of reading and lowering source; the read must succeed.
  def lower(source)
    parsed = Statifier::XML.parse(source)
    flunk "expected a parse, got #{parsed.error.message}" unless parsed.ok?
    Statifier::Lowering.lower(parsed.value, source)
  end

  # The chart source lowers to, failing the test when it is refused.
  def chart(source)
    result = lower(source)
    flunk "expected a chart, got #{result.errors.map(&:message)}" unless result.ok?
    result.value
  end

  # The chart of `<scxml>` around body.
  def chart_of(body) = chart(%(<scxml xmlns="#{SCXML}">#{body}</scxml>))

  # The first state of the chart of body.
  def state_of(body) = chart_of(body).states.first

  # The executable content of the first onentry block of the first state.
  def content_of(body) = state_of("<state><onentry>#{body}</onentry></state>").onentry.first.content

  # Each refusal of source as [reason, detail, line, column]; the source
  # must be refused, with no chart.
  def refusals(source)
    result = lower(source)
    refute_predicate result, :ok?, "expected #{source.inspect} to be refused"
    assert_nil result.value
    result.errors.map { |error| [error.reason, error.detail, error.location.start_line, error.location.start_column] }
  end

  # The named fields of node, in order.
  def fields(node, *names) = names.map { node.public_send(_1) }

  # The named field of each node.
  def each_of(nodes, name) = nodes.map { _1.public_send(name) }

  # The text a span covers in source.
  def slice(location, source) = location.slice(source)

  # The line, column and byte offset a span starts at, then where it ends.
  def span_of(location)
    [location.start_line, location.start_column, location.start_offset,
     location.end_line, location.end_column, location.end_offset]
  end
end
