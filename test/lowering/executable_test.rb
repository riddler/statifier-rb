# frozen_string_literal: true

require "test_helper"
require_relative "lowering_helper"

# Executable content: what each element's node holds.
class LoweringExecutableTest < Minitest::Test
  include LoweringHelper

  D = Internals::Document

  # sabotage: split a raise's event (Reading.list for "event" in
  # Executable.raise_node); the assert_equal on the event fails.
  def test_a_raise_keeps_its_event_as_one_string_and_a_log_its_label_and_expr
    raise_node, log = content_of(%(<raise event="a b"/><log label="l" expr="x + 1"/>))

    assert_equal "a b", raise_node.event
    assert_equal ["l", "x + 1", %i[label expr]], [log.label, log.expr, log.attribute_locations.keys]
  end

  # sabotage: give an assign its element span as location (location:
  # element.location in Executable.assign); the assert_equal on the path
  # fails.
  def test_an_assign_keeps_its_location_attribute_apart_from_its_span
    source = %(<scxml><state><onentry><assign location="v.w" expr="1"/></onentry></state></scxml>)
    assign = chart(source).states.first.onentry.first.content.first

    assert_equal ["v.w", "1", nil, nil, ""], [assign.location, assign.expr, assign.markup, assign.markup_location,
                                              assign.text]
    assert_equal %(<assign location="v.w" expr="1"/>), slice(assign.node_location, source)
  end

  # sabotage: start the markup at the first child, blank text included
  # (drop the blank-text reject in DataModel.markup); the assert_equal on
  # the markup fails.
  def test_an_assigns_markup_spans_its_first_to_last_significant_child_line_breaks_as_written
    source = "<scxml><state><onentry><assign location=\"v\">\r\n <a>\r\n</a> t <b/>\r\n</assign>" \
             "</onentry></state></scxml>"
    assign = chart(source).states.first.onentry.first.content.first

    assert_equal "<a>\r\n</a> t <b/>", assign.markup
    assert_equal assign.markup, slice(assign.markup_location, source)
    assert_equal "\n  t \n", assign.text
  end

  # sabotage: drop an `<elseif>` instead of opening a branch with it
  # (`when :elseif then next` in Executable.partition); the assert_equal
  # on the conditions fails.
  def test_an_if_is_partitioned_into_branches_at_each_elseif_and_else
    if_node = content_of(<<~XML).first
      <if cond="a"><raise event="e1"/><log/><elseif cond="b"/><raise event="e2"/><else/><raise event="e3"/></if>
    XML

    branches = if_node.branches

    assert_equal ["a", "b", nil], each_of(branches, :cond)
    classes = each_of(branches, :content).map { _1.map(&:class) }

    assert_equal [[D::Raise, D::Log], [D::Raise], [D::Raise]], classes
    assert_equal if_node.location, branches.first.location
    assert_equal [[:cond], [:cond], []], each_of(branches, :attribute_locations).map(&:keys)
  end

  # sabotage: read item from "array" in Executable.foreach_node; the
  # assert_equal on the item fails.
  def test_a_foreach_reads_array_item_and_index_and_holds_its_content
    foreach, bare = content_of(%(<foreach array="xs" item="x" index="i"><log/></foreach>) +
                               %(<foreach array="ys" item="y"/>))

    assert_equal ["xs", "x", "i", [D::Log]], [foreach.array, foreach.item, foreach.index, foreach.content.map(&:class)]
    assert_nil bare.index
  end

  # sabotage: trim a script's text (Reading.text(element).strip in
  # Executable.script); the assert_equal on the text fails.
  def test_a_script_keeps_its_text_as_written
    document = chart_of(%(<script>\n  x = 1 &amp;&amp; <![CDATA[y < 2]]>\n</script>))

    assert_equal "\n  x = 1 && y < 2\n", document.scripts.first.text
    assert_nil document.scripts.first.src
  end

  # sabotage: read targetexpr from "target" in Executable.send_node; the
  # assert_equal on the fields fails.
  def test_a_send_reads_every_attribute_and_holds_its_params_and_content
    send_node = content_of(<<~XML).first
      <send event="e" eventexpr="ee" target="t" targetexpr="te" type="ty" typeexpr="tye" id="i" idlocation="il"
            delay="1s" delayexpr="de" namelist=" a  b "><param name="p1"/><content expr="c"/><param name="p2"/></send>
    XML

    assert_equal %w[e ee t te ty tye i il 1s de],
                 fields(send_node, :event, :eventexpr, :target, :targetexpr, :type, :typeexpr, :id, :idlocation,
                        :delay, :delayexpr)
    assert_equal [%w[a b], %w[p1 p2], "c"], [send_node.namelist, send_node.params.map(&:name), send_node.content.expr]
    assert_equal 11, send_node.attribute_locations.size
  end

  # sabotage: read sendidexpr from "sendid" in Executable.cancel; the
  # assert_equal on the fields fails.
  def test_a_cancel_reads_sendid_and_sendidexpr
    cancel = content_of(%(<cancel sendid="s" sendidexpr="se"/>)).first

    assert_equal %w[s se], [cancel.sendid, cancel.sendidexpr]
  end

  # sabotage: reject every executable child of a block but raise (CONTENT
  # keyed by Document::Raise); the assert_equal on the classes fails.
  def test_a_block_holds_every_kind_of_executable_content_in_document_order
    content = content_of(%(<send/><raise event="a"/><log/><assign location="x"/><if cond="c"/>) +
                         %(<foreach array="a" item="b"/><script/><cancel/>))

    assert_equal [D::Send, D::Raise, D::Log, D::Assign, D::If, D::Foreach, D::Script, D::Cancel], content.map(&:class)
  end
end
