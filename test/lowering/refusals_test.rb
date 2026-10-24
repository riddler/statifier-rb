# frozen_string_literal: true

require "test_helper"
require_relative "lowering_helper"

# What does not lower: each refusal's reason, detail and position, and
# that every refusal is answered, in document order, with no chart.
class LoweringRefusalsTest < Minitest::Test
  include LoweringHelper

  # sabotage: dispatch a root by its builder whatever its name (drop the
  # `unless name == "scxml"` refusal in Lowering.root_refusal); the
  # assert_equal on the state root fails.
  def test_refuses_a_root_that_is_not_scxml_or_is_foreign
    assert_equal [[:unexpected_root, { name: "state" }, 1, 1]], refusals(%(<s:state xmlns:s="#{SCXML}"/>))
    assert_equal [[:foreign_element, { name: "scxml", uri: "urn:x" }, 1, 1]], refusals(%(<scxml xmlns="urn:x"/>))
    assert_equal [[:foreign_element, { name: "scxml", uri: "" }, 1, 1]], refusals(%(<scxml xmlns=""/>))
  end

  # sabotage: dispatch `<scxml>` below the root (add "scxml" => [States,
  # :state] to BUILDERS); the assert_equal on the unsupported scxml fails.
  def test_refuses_an_element_no_builder_reads_scxml_below_the_root_included
    assert_equal [[:unsupported_element, { name: "s:bogus" }, 1, 50], [:unsupported_element, { name: "scxml" }, 1, 67]],
                 refusals(%(<scxml xmlns:s="#{SCXML}"><s:bogus/><state><scxml/></state></scxml>))
  end

  # sabotage: let an empty namespace dispatch (scxml? answering true for
  # ""); the assert_equal on the refusals fails.
  def test_refuses_an_element_in_another_namespace
    assert_equal [[:foreign_element, { name: "state", uri: "urn:x" }, 1, 8],
                  [:foreign_element, { name: "final", uri: "" }, 1, 30]],
                 refusals(%(<scxml><state xmlns="urn:x"/><final xmlns=""/></scxml>))
  end

  # sabotage: report every misplaced child under the name "state" (tag
  # :state in Placement.misplaced); the assert_equal on the names fails.
  def test_refuses_a_child_its_parent_has_no_place_for_naming_both
    source = %(<scxml><parallel/><transition/><s:state xmlns:s="#{SCXML}"><raise event="e"/></s:state>) \
             '<state><assign location="x"/><script/></state></scxml>'

    assert_equal [[:misplaced_element, { name: "transition", parent: "scxml" }, 1, 19],
                  [:misplaced_element, { name: "raise", parent: "s:state" }, 1, 83],
                  [:misplaced_element, { name: "assign", parent: "state" }, 1, 118],
                  [:misplaced_element, { name: "script", parent: "state" }, 1, 140]], refusals(source)
  end

  # sabotage: name a misplaced parallel by its kind (node.kind.to_s for a
  # :state tag in Placement.misplaced); the assert_equal on the name fails.
  def test_a_misplaced_state_of_any_kind_is_reported_as_state
    assert_equal [[:misplaced_element, { name: "state", parent: "onentry" }, 1, 24]],
                 refusals(%(<scxml><state><onentry><parallel/></onentry></state></scxml>))
  end

  # sabotage: let `<data>` walk its element children (no misplaced errors
  # in DataModel.data); the assert_equal on the refusals fails.
  def test_refuses_an_element_child_of_an_element_that_holds_only_text
    assert_equal [[:misplaced_element, { name: "x", parent: "data" }, 1, 32],
                  [:misplaced_element, { name: "y", parent: "script" }, 1, 63],
                  [:misplaced_element, { name: "z", parent: "elseif" }, 1, 122]],
                 refusals(%(<scxml><datamodel><data id="a"><x/></data></datamodel><script><y/></script>) +
                          %(<state><onentry><if cond="c"><elseif cond="d"><z/></elseif></if></onentry></state></scxml>))
  end

  # sabotage: drop the no-break space from Errors::TRIM; the first
  # assert_equal fails.
  def test_refuses_text_that_is_not_blank_where_there_is_no_room_for_it
    assert_equal [], lower("<scxml>\n\u00a0\u3000\t<state/> \u2007</scxml>").errors
    assert_equal [[:stray_text, { text: "x  y" }, 1, 15]], refusals("<scxml><state>\n x  y \n</state></scxml>")
  end

  # sabotage: cut the preview at 10 (Errors::PREVIEW = 10); the
  # assert_equal on the message fails.
  def test_a_stray_text_message_quotes_a_preview_of_forty_characters
    error = lower("<scxml>#{"a" * 41} &quot; \\ \#{</scxml>").errors.first

    assert_equal %(stray text "#{"a" * 40}..." is not allowed here), error.message
    assert_equal 'stray text "q\\"\\n\\\\ \\#{" is not allowed here',
                 lower("<scxml>q\"\n\\ \#{<state/></scxml>").errors.first.message
  end

  # sabotage: make an attribute optional by answering an empty node
  # (Executable.required yielding "" for a missing value); the
  # assert_equal on the refusals fails.
  def test_refuses_a_missing_required_attribute
    source = %(<scxml><datamodel><data/></datamodel><state><invoke><param/></invoke><onentry><raise/>) +
             %(<assign/><if><log/></if></onentry></state></scxml>)

    assert_equal [[:missing_attribute, { element: "data", attribute: "id" }, 1, 19],
                  [:missing_attribute, { element: "param", attribute: "name" }, 1, 53],
                  [:missing_attribute, { element: "raise", attribute: "event" }, 1, 79],
                  [:missing_attribute, { element: "assign", attribute: "location" }, 1, 87],
                  [:missing_attribute, { element: "if", attribute: "cond" }, 1, 96]], refusals(source)
  end

  # sabotage: stop at the first missing foreach attribute (missing.first(1)
  # in Executable.foreach); the assert_equal on both refusals fails.
  def test_a_foreach_missing_both_attributes_reports_both
    assert_equal(%w[item array], refusals(%(<scxml><state><foreach/></state></scxml>)).map { _1[1][:attribute] })
    assert_equal(%w[array item], refusals(%(<scxml><foreach/></scxml>)).map { _1[1][:attribute] })
  end

  # sabotage: report every attribute of an else (map over all attributes
  # in Executable.else_node); the assert_equal on the one refusal fails.
  def test_refuses_the_first_attribute_on_an_else_at_its_span
    assert_equal [[:unexpected_attribute, { element: "else", attribute: "cond" }, 1, 43]],
                 refusals(%(<scxml><state><onentry><if cond="a"><else cond="b" x="1"/></if></onentry></state></scxml>))
  end

  # sabotage: lower a script src as an ordinary script (drop the src check
  # in Executable.script); the assert_equal on the refusal fails.
  def test_refuses_a_script_with_src
    assert_equal [[:unsupported_attribute, { element: "script", attribute: "src" }, 1, 8]],
                 refusals(%(<scxml><script src="a.js"/></scxml>))
  end

  # sabotage: answer the errors in the order found (Lowering.refuse not
  # sorting); the assert_equal on the lines fails. The raise missing its
  # event makes no node, so it is not misplaced too.
  def test_answers_every_refusal_in_document_order_and_no_chart
    source = "<scxml>\n<state>\n<raise/>\n</state>\nx\n<bogus/>\n<final><onentry><raise/></onentry>y</final>\n</scxml>"

    assert_equal([[:missing_attribute, 3], [:stray_text, 4], [:unsupported_element, 6], [:missing_attribute, 7],
                  [:stray_text, 7]], refusals(source).map { [_1[0], _1[2]] })
  end

  # sabotage: leave the error detail unfrozen (drop .freeze after
  # transform_values in Errors.make); the assert fails.
  def test_a_refusal_is_deeply_frozen
    assert Ractor.shareable?(lower(%(<scxml><state><raise/>x</state></scxml>)))
  end
end
