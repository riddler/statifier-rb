# frozen_string_literal: true

require "test_helper"
require_relative "xml_helper"

# The shape of what a parse answers: a result value, an immutable tree, and
# the encodings a document is read from.
class ResultTest < Minitest::Test
  include XMLHelper

  # sabotage: answer error: :none for a read document in XML.parse; the
  # assert_predicate on ok? fails.
  def test_answers_a_result_holding_the_root_or_the_error
    read = Statifier::XML.parse("<a/>")
    refused = Statifier::XML.parse("<a>")

    assert_predicate read, :ok?
    assert_equal ["a", nil], [read.value.name, read.error]
    refute_predicate refused, :ok?
    assert_kind_of Statifier::XML::ParseError, refused.error
  end

  # sabotage: leave the children array unfrozen in OpenElement#finish
  # (children: children); the assert_predicate on the children fails.
  def test_answers_a_frozen_tree
    element = root("<a x='1'>t<b/></a>")
    attribute = element.attributes.first

    [element, element.attributes, element.children, element.name, attribute.name, attribute.value,
     element.children.first.value].each { assert_predicate _1, :frozen? }
  end

  # sabotage: transcode a binary string in XML.transcode (drop BINARY from
  # READ_AS_BYTES); the assert_equal on the binary document's text fails.
  def test_reads_a_binary_or_ascii_string_from_its_bytes_and_transcodes_any_other
    assert_equal "\u{E9}", text_value("<a>\u{E9}</a>".b)
    assert_equal "e", text_value("<a>e</a>".encode(Encoding::US_ASCII))
    assert_equal "\u{E9}", text_value("<a>\u{E9}</a>".encode(Encoding::UTF_16LE))
  end

  # sabotage: let XML.transcode raise (drop its rescue); the flunk in
  # XMLHelper#parse fails.
  def test_refuses_a_string_that_cannot_become_utf8
    assert_refused "<a>\x81</a>".dup.force_encoding(Encoding::Windows_1252), :invalid_encoding, 1, 1
  end
end
