# frozen_string_literal: true

require "test_helper"
require_relative "interpreter_helper"

# The domain half of selection: the least common compound ancestor, the
# effective targets, the transition domain and the exit set.
class DomainTest < Minitest::Test
  include InterpreterHelper

  S = Internals::Interpreter::Selection

  NESTED = <<~XML
    <state id="s" initial="s1">
      <transition event="int" type="internal" target="s2"/>
      <transition event="ext" target="s2"/>
      <transition event="int.atomic" type="internal" target="s2"/>
      <transition event="loose"/>
      <state id="s1"><transition event="int.atomic" type="internal" target="s2"/></state>
      <state id="s2"/>
    </state>
  XML

  PARALLEL = <<~XML
    <state id="top">
      <parallel id="p">
        <state id="r1"><state id="a"><transition event="x" target="b"/></state><state id="a2"/></state>
        <state id="r2"><state id="b"/></state>
      </parallel>
    </state>
  XML

  HISTORY = <<~XML
    <state id="s" initial="s1">
      <history id="h"><transition target="s2"/></history>
      <state id="s1"/><state id="s2"/>
    </state>
    <state id="out"><transition event="back" target="h"/></state>
  XML

  # sabotage: answer machine.lcca(indexes.drop(1)) in Selection.find_lcca;
  # the assert_equal on top fails.
  def test_find_lcca_is_the_machine_s
    chart = machine(PARALLEL)

    assert_equal at(chart, "top"), S.find_lcca(chart, indexes(chart, "a", "b"))
  end

  # sabotage: answer nil in place of the recorded value in
  # Selection.effective_target_states; the assert_equal on s1 fails.
  def test_a_history_target_resolves_to_its_record_else_its_default
    chart = machine(HISTORY)
    back = transitions_of(chart, "out").first
    recorded = snapshot(chart, "out", history: { "h" => ["s1"] })

    assert_equal ["s2"], ids(chart, S.get_effective_target_states(snapshot(chart, "out"), back))
    assert_equal ["s1"], ids(chart, S.get_effective_target_states(recorded, back))
  end

  # sabotage: answer machine.lcca([source, *targets]) whatever the type in
  # Selection.get_transition_domain; the assert_equal on s fails.
  def test_an_internal_transition_into_its_own_compound_source_has_the_source_as_domain
    chart = machine(NESTED)
    internal, external = transitions_of(chart, "s")
    snap = snapshot(chart, "s", "s1")

    assert_equal at(chart, "s"), S.get_transition_domain(snap, internal)
    assert_equal 0, S.get_transition_domain(snap, external)
  end

  # sabotage: answer transition.type == :internal alone from
  # Selection.internal_domain?; the assert_equal on s fails, as s1 becomes
  # its own domain.
  def test_an_internal_transition_from_an_atomic_state_has_the_lcca_as_domain
    chart = machine(NESTED)
    atomic = transitions_of(chart, "s1").first

    assert_equal at(chart, "s"), S.get_transition_domain(snapshot(chart, "s", "s1"), atomic)
  end

  # sabotage: drop the compound? conjunct in Selection.internal_domain?; the
  # assert_equal on the root fails, as the parallel becomes its own domain.
  def test_an_internal_transition_from_a_parallel_into_it_has_the_lcca_as_domain
    chart = machine(<<~XML)
      <parallel id="p"><transition event="i" type="internal" target="b2"/>
        <state id="ra"><state id="a"/></state><state id="rb"><state id="b"/><state id="b2"/></state></parallel>
    XML
    internal = transitions_of(chart, "p").first

    assert_equal 0, S.get_transition_domain(snapshot(chart, "p", "ra", "a", "rb", "b"), internal)
  end

  # sabotage: answer source when targets is empty in
  # Selection.get_transition_domain; the assert_nil fails.
  def test_a_targetless_transition_has_no_domain_and_exits_nothing
    chart = machine(NESTED)
    loose = transitions_of(chart, "s").last
    snap = snapshot(chart, "s", "s1")

    assert_nil S.get_transition_domain(snap, loose)
    assert_empty S.compute_exit_set(snap, [loose])
  end

  # sabotage: let a compound? candidate include :parallel in Machine#lcca;
  # the assert_equal on top fails.
  def test_a_parallel_is_never_the_domain_of_a_cross_region_transition
    chart = machine(PARALLEL)
    cross = transitions_of(chart, "a").first

    assert_equal at(chart, "top"), S.get_transition_domain(snapshot(chart, "top", "p", "r1", "a", "r2", "b"), cross)
  end

  # sabotage: select descendant?(_1, domain) || _1 == domain in
  # Selection.compute_exit_set; the assert_equal on the internal exit set fails.
  def test_the_exit_set_is_the_active_proper_descendants_of_the_domain
    chart = machine(NESTED)
    internal, external = transitions_of(chart, "s")
    snap = snapshot(chart, "s", "s1")

    assert_equal ["s1"], ids(chart, S.compute_exit_set(snap, [internal]))
    assert_equal %w[s s1], ids(chart, S.compute_exit_set(snap, [external]))
  end

  # sabotage: drop the .sort in Selection.compute_exit_set; the
  # assert_equal on document order fails.
  def test_the_exit_set_is_one_set_in_document_order_across_transitions
    chart = machine(NESTED)
    internal, external = transitions_of(chart, "s")
    exit_set = S.compute_exit_set(snapshot(chart, "s", "s1"), [internal, external])

    assert_equal %w[s s1], ids(chart, exit_set)
    assert_predicate exit_set, :frozen?
  end

  # sabotage: select from every state index of the machine in place of the
  # configuration in Selection.compute_exit_set; the assert_equal fails on
  # a2.
  def test_the_exit_set_holds_no_inactive_state
    chart = machine(PARALLEL)
    cross = transitions_of(chart, "a").first

    snap = snapshot(chart, "top", "p", "r1", "a", "r2", "b")

    assert_equal %w[p r1 a r2 b], ids(chart, S.compute_exit_set(snap, [cross]))
  end
end
