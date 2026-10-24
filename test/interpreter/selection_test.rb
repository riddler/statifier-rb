# frozen_string_literal: true

require "test_helper"
require_relative "interpreter_helper"

# The selection walks: document order, a descendant preempting an
# ancestor, the condition seam and its failures, and the eventless walk.
class SelectionTest < Minitest::Test
  include InterpreterHelper

  S = Statifier::Interpreter::Selection

  NESTED = <<~XML
    <state id="p" initial="c">
      <transition event="e" target="z"/>
      <state id="c"><transition event="e" target="d"/><transition event="e" target="z"/></state>
      <state id="d"/>
    </state>
    <state id="z"/>
  XML

  # sabotage: walk machine.proper_ancestors(atomic) before atomic in
  # Selection.selected_for_atomic_state; the assert_equal on c fails.
  def test_a_descendant_transition_preempts_an_ancestor_s_and_document_order_breaks_ties
    chart = machine(NESTED)
    selected = S.select_transitions(snapshot(chart, "p", "c"), "e", data(chart)).transitions
    taken = selected.map { [chart.state(_1.source).id, ids(chart, _1.targets)] }

    assert_equal [["c", ["d"]]], taken
  end

  # sabotage: answer true when evaluated.ok? in Selection.enabled?; the
  # assert_equal on the second transition fails.
  def test_a_false_condition_passes_to_the_next_transition
    chart = machine(<<~XML)
      <state id="a"><transition event="e" cond="false" target="b"/><transition event="e" cond="true" target="c"/></state>
      <state id="b"/><state id="c"/>
    XML
    selected = S.select_transitions(snapshot(chart, "a"), "e", data(chart))

    assert_equal ["c"], ids(chart, selected.transitions.first.targets)
  end

  FAILING = <<~XML
    <state id="a"><transition event="e" cond="nope" target="b"/><transition event="e" cond="1" target="b"/>
      <transition event="e" target="c"/><transition event="e" cond="never_read" target="b"/></state>
    <state id="b"/><state id="c"/>
  XML

  # sabotage: skip the raised << in Selection.enabled?; the assert_equal on
  # the raised origins fails.
  def test_failed_conditions_raise_error_execution_in_walk_order
    chart = machine(FAILING)
    raised = S.select_transitions(snapshot(chart, "a"), "e", data(chart)).raised
    origins = chart.state(at(chart, "a")).transitions.first(2).map { { kind: :transition, t_index: _1 } }

    assert_equal(origins.map { ["error.execution", _1] }, raised.map { [_1.name, _1.origin] })
  end

  # sabotage: answer true in place of false after the raise in
  # Selection.enabled?; the assert_equal on c fails, as the failing one is
  # taken.
  def test_a_transition_whose_condition_failed_is_not_taken
    chart = machine(FAILING)
    taken = S.select_transitions(snapshot(chart, "a"), "e", data(chart)).transitions

    assert_equal([["c"]], taken.map { ids(chart, _1.targets) })
  end

  # sabotage: build the ExecutionError with reason: nil in
  # Selection.enabled?; the assert_instance_of on the first reason fails.
  def test_a_failed_condition_carries_its_reason
    chart = machine(FAILING)
    reasons = S.select_transitions(snapshot(chart, "a"), "e", data(chart)).raised.map(&:reason)

    assert_instance_of Statifier::Datamodel::EvaluatorError, reasons.first
    assert_equal Statifier::Datamodel::NonBooleanCond.new(value: 1), reasons.last
  end

  # sabotage: build the context over an empty configuration in
  # Selection.context; the assert on true fails.
  def test_condition_match_reads_the_datamodel_and_the_configuration
    chart = machine(<<~XML)
      <state id="a"><transition event="e" cond="In('a') &amp;&amp; x == 2" target="b"/></state><state id="b"/>
    XML
    transition = transitions_of(chart, "a").first

    assert S.condition_match(snapshot(chart, "a"), transition, data(chart, { "x" => 2 })).value
    refute S.condition_match(snapshot(chart, "b"), transition, data(chart, { "x" => 2 })).value
  end

  # sabotage: answer !eventless for the nil tokens case in
  # Selection.enabled?; both assert_equal calls fail.
  def test_the_eventless_and_the_event_walks_each_take_only_their_own_transitions
    chart = machine(<<~XML)
      <state id="a"><transition event="e" target="b"/><transition target="c"/></state><state id="b"/><state id="c"/>
    XML
    snap = snapshot(chart, "a")

    assert_equal ["c"], ids(chart, S.select_eventless_transitions(snap, data(chart)).transitions.first.targets)
    assert_equal ["b"], ids(chart, S.select_transitions(snap, "e", data(chart)).transitions.first.targets)
  end

  # sabotage: drop the name_match? conjunct in Selection.enabled?; the
  # assert_empty fails, as c's transition is taken.
  def test_an_event_no_descriptor_matches_selects_nothing
    chart = machine(NESTED)
    selected = S.select_transitions(snapshot(chart, "p", "c"), "ee.go", data(chart))

    assert_empty selected.transitions
    assert_empty selected.raised
  end

  # sabotage: drop the .uniq(&:t_index) in Selection.round; the
  # assert_equal on one transition fails, as a targetless transition
  # conflicts with nothing, itself included.
  def test_a_transition_two_atomic_states_reach_is_taken_once
    chart = machine(<<~XML)
      <parallel id="p"><transition event="e"/><state id="a"/><state id="b"/></parallel>
    XML

    assert_equal ["p"], selected_sources(chart, "e", "p", "a", "b")
  end
end
