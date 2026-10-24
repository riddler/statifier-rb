# frozen_string_literal: true

require "test_helper"
require_relative "lowering_helper"

# The state family, `<initial>`, `<transition>` and the blocks.
class LoweringStatesTest < Minitest::Test
  include LoweringHelper

  # sabotage: lower `<final>` with kind :state (States.final passing
  # :state); the assert_equal on the kinds fails.
  def test_one_node_kind_per_state_element
    states = chart_of(%(<state id="a"/><parallel id="b"/><final id="c"/>)).states

    assert_equal %i[state parallel final], states.map(&:kind)
    assert_equal [nil, nil, nil], states.map(&:history_type)
  end

  # sabotage: map "deep" to :shallow in States::HISTORY_TYPES; the
  # assert_equal on the types fails.
  def test_a_history_type_is_shallow_unless_written_deep_and_keeps_its_span
    source = %(<scxml><state><history/><history type="deep"/><history type="sideways"/></state></scxml>)
    histories = chart(source).states.first.states

    assert_equal [%i[history history history], %i[shallow deep shallow]],
                 [each_of(histories, :kind), each_of(histories, :history_type)]
    assert_equal [[], [:type], [:type]], each_of(histories, :attribute_locations).map(&:keys)
    assert_equal "sideways", slice(histories.last.attribute_locations[:type], source)
  end

  PARENT = <<~XML
    <state id="p" initial="x y"><transition event="e1"/><onentry/><state id="x"/><onexit/>
    <invoke id="i1"/><onentry><raise event="r"/></onentry><transition event="e2"/><final id="y"/>
    <invoke id="i2"/><initial><transition target="x"/></initial><donedata/><datamodel/></state>
  XML

  # sabotage: place `<onentry>` blocks into onexit (onentry: %i[onexit
  # many] in STATE_SLOTS); the assert_equal on the onentry blocks fails.
  def test_a_state_holds_its_states_transitions_and_blocks_in_document_order
    state = state_of(PARENT)

    assert_equal ["p", %w[x y], %w[x y]], [state.id, state.initial, each_of(state.states, :id)]
    assert_equal [["e1"], ["e2"]], each_of(state.transitions, :event)
    events = each_of(state.onentry, :content).map { _1.map(&:event) }

    assert_equal [[], ["r"]], events
  end

  # sabotage: place `<invoke>` children into states (invoke: %i[states
  # many] in STATE_SLOTS); the assert_equal on the invocations fails.
  def test_a_state_holds_its_invocations_initial_donedata_and_datamodel
    state = state_of(PARENT)

    assert_equal [%w[i1 i2], [["x"]]], [each_of(state.invoke, :id), each_of(state.initial_element.transitions, :target)]
    assert_equal [[]], each_of(state.onexit, :content)
    assert_kind_of Statifier::Document::Donedata, state.donedata
    assert_kind_of Statifier::Document::Datamodel, state.datamodel_element
  end

  # sabotage: keep the first `<initial>` (`||=` for a :one field in
  # Placement.fold); the assert_equal on the targets fails.
  def test_an_initial_holds_every_transition_written_and_the_last_initial_counts
    state = state_of(%(<state><initial><transition target="a"/></initial><initial>) +
                     %(<transition target="b"/><transition target="c"/></initial></state>))

    assert_equal [["b"], ["c"]], state.initial_element.transitions.map(&:target)
  end

  # sabotage: read cond as a list (Reading.list for "cond" in
  # States.transition); the assert_equal on the cond fails.
  def test_reads_a_transitions_attributes
    transition = state_of(%(<state><transition event="a b.c *" target=" s1  s2 " cond="x &gt; 1" ) +
                          %(type="internal"/></state>)).transitions.first

    assert_equal [%w[a b.c *], %w[s1 s2], "x > 1", :internal],
                 [transition.event, transition.target, transition.cond, transition.type]
  end

  # sabotage: map "external" to :internal in States::TRANSITION_TYPES; the
  # assert_equal on the explicit type fails.
  def test_a_transition_type_is_external_unless_written_internal
    types = state_of(%(<state><transition/><transition type="external"/><transition type="x"/></state>))
            .transitions.map(&:type)

    assert_equal %i[external external external], types
  end

  # sabotage: wrap a transition's content in a block (content:
  # [Document::Block.new(...)] in States.transition); the assert_equal on
  # the content classes fails.
  def test_a_transition_holds_its_executable_content_directly
    content = state_of(%(<state><transition><raise event="a"/><log expr="1"/></transition></state>))
              .transitions.first.content

    assert_equal [Statifier::Document::Raise, Statifier::Document::Log], content.map(&:class)
  end

  # sabotage: start a state's span at its first attribute (location:
  # element.attributes.first.location in States.state_like); the
  # assert_equal on the span fails.
  def test_carries_each_elements_span_from_its_less_than_sign
    source = %(<scxml>\n  <state id="a">\n    <transition target="b"/>\n  </state>\n</scxml>)
    state = chart(source).states.first

    assert_equal [2, 3, 10, 4, 11, 64], span_of(state.location)
    assert_equal %(<transition target="b"/>), slice(state.transitions.first.location, source)
    assert_equal "a", slice(state.attribute_locations[:id], source)
  end
end
