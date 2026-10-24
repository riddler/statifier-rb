# frozen_string_literal: true

require "test_helper"
require_relative "xml_helper"

# CDATA sections, the constructs that produce no node, and what the tree
# keeps as written.
class ConstructsTest < Minitest::Test
  include XMLHelper

  # sabotage: expand references inside a CDATA section (CDATA_RUN excluding
  # "&" and cdata_special calling read_reference); the assert_equal on
  # "a<b> &amp; c" fails.
  def test_takes_a_cdata_section_verbatim_and_coalesces_it_with_its_neighbours
    source = "<a>a<![CDATA[<b> &amp; ]]>c</a>"
    element = root(source)

    assert_equal 1, element.children.size
    assert_equal "a<b> &amp; c", text(element.children.first).value
    assert_equal "a<![CDATA[<b> &amp; ]]>c", element.children.first.location.slice(source)
  end

  # sabotage: start a run only for character data (read_cdata given a
  # throwaway +"" in read_content); the assert_equal on "x" fails.
  def test_makes_a_text_node_from_a_cdata_section_alone_even_an_empty_one
    assert_equal "x", text_value("<a><![CDATA[x]]></a>")
    assert_equal "", text_value("<a><![CDATA[]]></a>")
  end

  # sabotage: call flush before skip_comment in read_content; the
  # assert_equal on one child fails.
  def test_coalesces_text_across_a_comment_and_a_processing_instruction
    element = root("<a>x &amp;<!-- note -->y<?pi data?>z</a>")

    assert_equal 1, element.children.size
    assert_equal "x &yz", text(element.children.first).value
  end

  # sabotage: start a run in read_content's comment branch (call run_buffer
  # there); the assert_empty on the children fails.
  def test_makes_no_node_for_a_comment_or_processing_instruction_alone
    assert_empty root("<a><!-- only --><?pi x?></a>").children
  end

  # sabotage: drop the "<!DOCTYPE" branch from skip_misc; the parse is
  # refused and root flunks.
  def test_skips_the_declaration_comments_a_doctype_and_trailing_misc
    source = %(<?xml version="1.0" encoding="UTF-8"?>\n<!-- l -->\n<!DOCTYPE a [ <!ELEMENT a ANY> ]>\n) +
             %(<?pi x?>\n<a xmlns="urn:x"/>\n<!-- after -->\n<?pi y?>\n)

    assert_equal '<a xmlns="urn:x"/>', root(source).location.slice(source)
  end

  # sabotage: make DoctypeEnds stop at the first ">" outside square brackets
  # (return [@bracket, @bracket]); the assert_equal on column 26 fails.
  def test_ends_a_doctype_where_the_reference_does
    assert_equal [1, 26], start_of(root("<!DOCTYPE a [<!-- ] -->]><a/>"))
    assert_equal "a", root(%(<!DOCTYPE a [<!-- " -->"]><a/>)).name
    assert_equal [2, 1], start_of(root("<!DOCTYPE s [<!-- it's -->]>\n<s/>"))
  end

  # sabotage: keep whitespace-only runs out (skip flush when the run is
  # blank); the assert_equal on the child kinds fails.
  def test_keeps_whitespace_only_text_runs
    element = root("<a>\n  <b/>\n</a>")

    assert_equal [Statifier::XML::Text, Statifier::XML::Element, Statifier::XML::Text], element.children.map(&:class)
    assert_equal "\n  ", element.children.first.value
  end

  # sabotage: build the attributes as a Hash by name in read_attributes
  # (attributes.to_h { [_1.name, _1] }.values); the assert_equal on the
  # three pairs fails.
  def test_keeps_duplicate_attributes_and_prefixed_names_as_written
    element = root('<p:a xmlns:p="urn:x" id="a" id="b"/>')

    assert_equal "p:a", element.name
    pairs = element.attributes.map { [_1.name, _1.value] }

    assert_equal [%w[xmlns:p urn:x], %w[id a], %w[id b]], pairs
  end

  # sabotage: read children by recursion (read_root calling itself per start
  # tag through a recursive helper); the run raises SystemStackError.
  def test_parses_deep_nesting_without_touching_the_call_stack
    depth = 20_000
    node = root(("<s>" * depth) + ("</s>" * depth))
    seen = 1
    while (child = node.children.first)
      node = child
      seen += 1
    end

    assert_equal depth, seen
  end
end
