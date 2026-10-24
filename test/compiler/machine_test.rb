# frozen_string_literal: true

require "test_helper"
require_relative "compiler_helper"

# The machine's hierarchy queries, each an integer comparison or a walk up
# the parents over the interned indexes.
class MachineTest < Minitest::Test
  include CompilerHelper

  # 0 root; 1 a (2 a1, 3 h, 4 a2 (5 a21)); 6 p (7 r1, 8 r2); 9 f
  CHART = '<state id="a" initial="a1"><state id="a1"/><history id="h"><transition target="a1"/></history>' \
          '<state id="a2"><state id="a21"/></state></state><parallel id="p"><state id="r1"/>' \
          '<state id="r2"/></parallel><final id="f"/>'

  def setup = @m = machine(CHART)

  # sabotage: let a state be its own descendant (<= for < in
  # Machine#descendant?); the first refute fails.
  def test_descendant_is_proper_and_reads_the_range
    assert @m.descendant?(5, 1)
    assert @m.descendant?(9, 0)
    refute @m.descendant?(1, 1)
    refute @m.descendant?(6, 1)
  end

  # sabotage: count a parallel as compound (drop the kind test in
  # Machine#compound?); the first assert_equal fails.
  def test_kinds_answer_their_predicates
    assert_equal [true, false, false], [@m.compound?(1), @m.compound?(6), @m.compound?(2)]
    assert_equal [true, true, false], [@m.atomic?(2), @m.atomic?(9), @m.atomic?(1)]
    assert_equal [true, true, true], [@m.parallel?(6), @m.final?(9), @m.history?(3)]
    assert @m.compound?(0)
  end

  # sabotage: keep histories among the child states (answer children in
  # Machine#child_states); the first assert_equal fails.
  def test_child_states_leave_histories_out
    assert_equal [2, 4], @m.child_states(1)
    assert_equal [1, 6, 9], @m.child_states(0)
  end

  # sabotage: stop before the root (until parent.nil? || parent.zero? in
  # Machine#proper_ancestors); the first assert_equal fails.
  def test_proper_ancestors_run_nearest_first_to_the_root
    assert_equal [4, 1, 0], @m.proper_ancestors(5)
    assert_empty @m.proper_ancestors(0)
  end

  # sabotage: accept a parallel as the ancestor (drop compound? in
  # Machine#lcca); the assert_equal on the regions fails.
  def test_lcca_is_the_nearest_compound_ancestor_holding_every_index
    assert_equal 1, @m.lcca([5, 2])
    assert_equal 0, @m.lcca([7, 8])
    assert_equal 0, @m.lcca([2, 9])
    assert_nil @m.lcca([0])
    assert_nil @m.lcca([])
  end

  # sabotage: answer nil for a missing state (states[index] for states.fetch
  # in Machine#state); the assert_raises fails.
  def test_a_state_the_machine_does_not_hold_is_refused
    assert_raises(IndexError) { @m.state(10) }
  end
end
