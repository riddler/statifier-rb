# frozen_string_literal: true

require "test_helper"
require_relative "interpreter_helper"

# The entry set: what a set of transitions enters, which compound states
# are entered by default, and which history default content runs.
class EnteringTest < Minitest::Test
  include InterpreterHelper

  E = Statifier::Interpreter::Entering

  PLAIN = <<~XML
    <state id="a"><transition event="e" target="c"/><transition event="f" target="b"/><transition event="g" target="p"/>
      <transition event="h" target="x1"/><transition event="none"/></state>
    <state id="b"><state id="c"/><state id="d"/></state>
    <parallel id="p">
      <history id="ph"><transition target="r1"/></history>
      <state id="r1"><state id="x1"/><state id="x2"/></state>
      <state id="r2"><state id="y1"/></state>
    </parallel>
  XML

  # The entry set of the transition at `position` among a's.
  def entry_set_of(chart, position, *active, history: {})
    E.compute_entry_set(snapshot(chart, *active, history:), [transitions_of(chart, "a")[position]])
  end

  # The entry set's three members as ids, the history content by parent id.
  def members(chart, entry_set)
    [ids(chart, entry_set.states_to_enter), ids(chart, entry_set.states_for_default_entry),
     entry_set.default_history_content.to_h { |parent, t_index| [chart.state(parent).id, t_index] }]
  end

  # sabotage: drop the add_ancestor_states_to_enter reduce in
  # Entering.compute_entry_set; the assert_equal loses b.
  def test_an_atomic_target_enters_itself_and_its_ancestors_up_to_the_domain
    chart = machine(PLAIN)

    assert_equal [%w[b c], [], {}], members(chart, entry_set_of(chart, 0, "a"))
  end

  # sabotage: drop .flag_default_entry(index) in
  # Entering.add_descendant_states_to_enter; the assert_equal on the flagged
  # b fails.
  def test_a_compound_target_enters_its_initial_chain_and_is_entered_by_default
    chart = machine(PLAIN)

    assert_equal [%w[b c], ["b"], {}], members(chart, entry_set_of(chart, 1, "a"))
  end

  # sabotage: use machine.state(index).children in place of child_states in
  # Entering.enter_uncovered_regions; the entry registers ph's default
  # content and the assert_equal fails.
  def test_a_parallel_target_enters_every_region_and_never_its_history
    chart = machine(PLAIN)

    assert_equal [%w[p r1 x1 r2 y1], %w[r1 r2], {}], members(chart, entry_set_of(chart, 2, "a"))
  end

  # sabotage: answer set without the uncovered regions in
  # Entering.add_ancestor_states_to_enter; the assert_equal loses r2 and y1.
  def test_a_target_in_one_region_enters_the_uncovered_sibling_region_by_default
    chart = machine(PLAIN)

    assert_equal [%w[p r1 x1 r2 y1], ["r2"], {}], members(chart, entry_set_of(chart, 3, "a"))
  end

  # sabotage: start the reduce in Entering.compute_entry_set from
  # EntrySet::EMPTY.add(0); the assert_equal on nothing fails.
  def test_a_targetless_transition_enters_nothing
    chart = machine(PLAIN)

    assert_equal [[], [], {}], members(chart, entry_set_of(chart, 4, "a"))
  end

  # sabotage: pass nil in place of domain to add_ancestor_states_to_enter in
  # Entering.compute_entry_set; the assert_equal on the internal entry gains s
  # and the root.
  def test_an_internal_transition_s_domain_bounds_the_ancestor_walk
    chart = machine(<<~XML)
      <state id="s" initial="s1"><transition event="i" type="internal" target="s2"/><transition event="x" target="s2"/>
        <state id="s1"/><state id="s2"/></state>
    XML
    internal, external = transitions_of(chart, "s")
    snap = snapshot(chart, "s", "s1")

    assert_equal ["s2"], ids(chart, E.compute_entry_set(snap, [internal]).states_to_enter)
    assert_equal %w[s s2], ids(chart, E.compute_entry_set(snap, [external]).states_to_enter)
  end

  HISTORY = <<~XML
    <state id="out"><transition event="back" target="h"/><transition event="deep" target="dh"/></state>
    <state id="s" initial="c">
      <history id="h"><transition target="d"/></history>
      <history id="dh" type="deep"><transition target="d"/></history>
      <state id="c"><state id="c1"/><state id="c2"/></state>
      <state id="d"/>
      <parallel id="p">
        <state id="r1"><state id="x1"/><state id="x2"/></state>
        <state id="r2"><state id="y1"/><state id="y2"/></state>
      </parallel>
    </state>
  XML

  # The entry set of out's transition at `position`, with `history`.
  def history_entry(chart, position, history)
    E.compute_entry_set(snapshot(chart, "out", history:), [transitions_of(chart, "out")[position]])
  end

  # sabotage: register the content when recorded is not nil in
  # Entering.enter_history_target; the assert_equal on the empty map fails.
  def test_a_recorded_shallow_history_restores_its_children_each_by_its_own_default
    chart = machine(HISTORY)

    assert_equal [%w[s c c1], ["c"], {}], members(chart, history_entry(chart, 0, { "h" => ["c"] }))
  end

  # sabotage: drop the recorded-value return in
  # Entering.enter_history_target; the assert_equal fails, as d enters in
  # place of x2 and y2.
  def test_a_recorded_deep_history_restores_its_atomic_states_across_a_parallel
    chart = machine(HISTORY)

    assert_equal [%w[s p r1 x2 r2 y2], [], {}], members(chart, history_entry(chart, 1, { "dh" => %w[x2 y2] }))
  end

  # sabotage: key the content by history_index in place of history.parent
  # in Entering.enter_history_target; the assert_equal on the map fails.
  def test_an_unrecorded_history_follows_its_default_and_registers_its_content_on_the_parent
    chart = machine(HISTORY)
    default = chart.state(at(chart, "h")).history_default

    assert_equal [%w[s d], [], { "s" => default }], members(chart, history_entry(chart, 0, {}))
  end

  # sabotage: drop the frozen sort in EntrySet#put (answer set + [index]);
  # the assert_equal on the ascending order fails.
  def test_the_entry_set_is_frozen_and_ascending
    chart = machine(PLAIN)
    entry_set = E.add_ancestor_states_to_enter(snapshot(chart), at(chart, "y1"), nil,
                                               Statifier::Interpreter::EntrySet::EMPTY.add(at(chart, "y1")))

    assert_equal %w[scxml p r1 x1 r2 y1], ids(chart, entry_set.states_to_enter)
    assert_predicate entry_set.states_to_enter, :frozen?
  end
end
