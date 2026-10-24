# frozen_string_literal: true

require "test_helper"
require_relative "interpreter_helper"

# Conflict removal: which of the enabled transitions fire together.
class ConflictTest < Minitest::Test
  include InterpreterHelper

  S = Statifier::Interpreter::Selection

  # sabotage: answer filtered (never append) in
  # Selection.remove_conflicting_transitions; the assert_equal on both fails.
  def test_regions_of_a_parallel_keep_non_conflicting_transitions_in_document_order
    chart = machine(<<~XML)
      <parallel id="p">
        <state id="r1"><state id="a"><transition event="e" target="a2"/></state><state id="a2"/></state>
        <state id="r2"><state id="b"><transition event="e" target="b2"/></state><state id="b2"/></state>
      </parallel>
    XML

    assert_equal %w[a b], selected_sources(chart, "e", "p", "r1", "a", "r2", "b")
  end

  # sabotage: answer [] in place of nil when the kept one preempts in
  # Selection.resolve; the assert_equal gains b.
  def test_on_a_conflict_between_unrelated_sources_the_earlier_wins
    chart = machine(<<~XML)
      <parallel id="p">
        <state id="r1"><state id="a"><transition event="e" target="out"/><transition event="f" target="a2"/></state><state id="a2"/></state>
        <state id="r2"><state id="b"><transition event="e" target="b2"/><transition event="f" target="out"/></state><state id="b2"/></state>
      </parallel>
      <state id="out"/>
    XML
    snap = snapshot(chart, "p", "r1", "a", "r2", "b")

    taken = %w[e f].map { sources(chart, S.select_transitions(snap, _1, data(chart)).transitions) }

    assert_equal [["a"], ["a"]], taken
  end

  # sabotage: swap the arguments of descendant? in Selection.resolve; the
  # assert_equal on c fails.
  def test_on_a_conflict_a_descendant_source_preempts_an_ancestor_s_in_either_order
    chart = machine(<<~XML)
      <state id="p" initial="c"><transition event="e" target="z"/><state id="c"><transition event="e" target="z"/></state></state>
      <state id="z"/>
    XML
    outer = transitions_of(chart, "p").first
    inner = transitions_of(chart, "c").first
    snap = snapshot(chart, "p", "c")

    assert_equal ["c"], sources(chart, S.remove_conflicting_transitions(snap, [outer, inner]))
    assert_equal ["c"], sources(chart, S.remove_conflicting_transitions(snap, [inner, outer]))
  end

  # sabotage: answer true from Selection.conflict?; the assert_equal loses
  # b.
  def test_a_targetless_transition_conflicts_with_nothing
    chart = machine(<<~XML)
      <parallel id="p">
        <state id="r1"><state id="a"><transition event="e"/></state></state>
        <state id="r2"><state id="b"><transition event="e" target="out"/></state></state>
      </parallel>
      <state id="out"/>
    XML

    assert_equal %w[a b], selected_sources(chart, "e", "p", "r1", "a", "r2", "b")
  end
end
