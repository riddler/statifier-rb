# frozen_string_literal: true

require "test_helper"
require_relative "compiler_helper"

# The interning: states, transitions, content nodes and data, each numbered
# in document order, with the hierarchy indexes and the default entries the
# reference resolves.
class CompilerIndexesTest < Minitest::Test
  include CompilerHelper

  NESTED = '<state id="a" initial="a2"><state id="a1"/><state id="a2"><state id="a21"/></state></state>' \
           '<parallel id="p"><state id="r1"/><state id="r2"/></parallel><final id="f"/>'

  DEFAULTS = '<state id="a" initial="a2"><state id="a1"/><state id="a2"/></state>' \
             '<state id="b"><initial><transition target="b2"/></initial><state id="b1"/><state id="b2"/>' \
             '</state><state id="c"><state id="c1"/></state><parallel id="p"><state id="r"/></parallel>'

  TRANSITIONS = '<state id="a"><initial><transition target="a1"/></initial><transition event="x" target="b"/>' \
                '<state id="a1"><transition event="y" target="a"/></state></state><state id="b" initial="b1">' \
                '<history id="h"><transition target="b1"/></history><state id="b1"/></state>'

  CONTENT = '<state id="a"><onentry><raise event="r"/><if cond="true"><log expr="1"/></if></onentry>' \
            '<onexit><foreach array="[1]" item="i"><raise event="s"/></foreach></onexit>' \
            '<transition target="a"><raise event="t"/></transition>' \
            '<invoke type="x"><finalize><raise event="u"/></finalize></invoke></state>'

  # sabotage: start a state's children at its own index (index for index + 1
  # in Numbering#numbered); the assert_equal on the ids fails.
  def test_states_are_indexed_in_document_order_the_root_at_zero
    states = machine(NESTED).states

    assert_equal [nil, "a", "a1", "a2", "a21", "p", "r1", "r2", "f"], states.map(&:id)
    assert_equal (0..8).to_a, states.map(&:index)
    assert_equal %i[scxml state state state state parallel state state final], states.map(&:kind)
  end

  # sabotage: answer after as last (drop the - 1 in Numbering#numbered); the
  # assert_equal on the last indexes fails.
  def test_each_state_knows_its_parent_children_and_descendant_range
    states = machine(NESTED).states

    assert_equal [nil, 0, 1, 1, 3, 0, 5, 5, 0], states.map(&:parent)
    assert_equal [8, 4, 2, 4, 4, 7, 6, 7, 8], states.map(&:last)
    assert_equal [[1, 5, 8], [2, 3], [], [4], [], [6, 7], [], [], []], states.map(&:children)
  end

  # sabotage: skip the initial attribute (drop its return in
  # Numbering#resolve_initial); the assert_equal fails.
  def test_default_entries_follow_the_specifications_precedence
    initials = machine(DEFAULTS).states.map(&:initial)

    assert_equal [[1], [3], [6], [8], []], initials.values_at(0, 1, 4, 7, 9)
  end

  # sabotage: resolve the root's initial as its first child always (drop the
  # attribute branch in Walk#root_initial); the assert_equal fails.
  def test_the_roots_initial_attribute_resolves_to_its_indexes
    assert_equal [2], machine('<state id="a"/><state id="b"/>', %(#{ROOT} initial="b")).state(0).initial
  end

  # sabotage: number the <initial> element's transitions before the plain ones
  # (in Numbering#transition_parts); the assert_equal on the sources fails.
  def test_transitions_are_numbered_plain_then_initial_state_by_state
    m = machine(TRANSITIONS)

    assert_equal([[0, 1, [3]], [1, 1, [2]], [2, 2, [1]], [3, 4, [5]]],
                 m.transitions.map { [_1.t_index, _1.source, _1.targets] })
  end

  # sabotage: keep a history's transitions selectable (plain for EMPTY as its
  # transitions in Numbering#transition_parts); the first assert_equal fails.
  def test_a_state_holds_its_transitions_its_initial_transition_and_a_historys_default
    m = machine(TRANSITIONS)
    parts = [1, 4].map { |at| m.state(at).to_h.values_at(:transitions, :initial_transition, :history_default) }

    assert_equal [[[0], 1, nil], [[], nil, 3]], parts
    assert_equal [4], m.state(3).history_children
  end

  # sabotage: split an event without keeping an empty part (drop the -1 in
  # Numbering#events); the assert_equal fails.
  def test_event_descriptors_split_on_their_dots
    m = machine('<state id="a"><transition event="e.go f a." target="a"/></state>')

    assert_equal [%w[e go], %w[f], ["a", ""]], m.transitions.first.events
  end

  # sabotage: take an <if>'s index after its branches (c_index: next_c_index
  # in Content#if_node); the assert_equal fails.
  def test_content_nodes_are_numbered_containers_first
    entry = machine(CONTENT).state(1).onentry.first.content

    assert_equal [0, 1, 2], [entry[0], entry[1], entry[1].branches.first.content.first].map(&:c_index)
  end

  # sabotage: number a loop body before the loop (content_list, then
  # next_c_index, at the top of Content#foreach); the assert_equal fails.
  def test_a_loop_takes_its_index_before_its_body
    foreach = machine(CONTENT).state(1).onexit.first.content.first

    assert_equal [3, 4], [foreach.c_index, foreach.content.first.c_index]
  end

  # sabotage: number a state's invokes before its transitions (data_parts
  # before transition_parts in Numbering#own_parts); the assert_equal fails.
  def test_transition_content_precedes_finalize_content
    m = machine(CONTENT)

    assert_equal [5, 6], [m.transitions.first.content.first.c_index,
                          m.state(1).invoke.first.finalize.content.first.c_index]
  end

  # sabotage: number the root's <data> after the states' (assign_data below
  # siblings in Walk#root); the first assert_equal fails.
  def test_data_is_numbered_the_roots_first_then_state_by_state
    m = machine('<datamodel><data id="x"/></datamodel><state id="a"><datamodel><data id="y"/><data id="z"/>' \
                '</datamodel><state id="b"><datamodel><data id="w"/></datamodel></state></state>')

    assert_equal([[0, "x"], [1, "y"], [2, "z"], [3, "w"]], m.data_elements.map { [_1.d_index, _1.id] })
    assert_equal [[0], [1, 2], [3]], m.states.map(&:data)
  end

  # sabotage: map a state with no id too (drop the nil test in
  # Numbering#numbered); the assert_equal on the keys fails.
  def test_id_to_index_holds_every_state_written_with_an_id
    m = machine('<state id="a"><state/><state id="b"/></state>')

    assert_equal({ "a" => 1, "b" => 3 }, m.id_to_index)
  end
end
