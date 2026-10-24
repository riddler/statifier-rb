# frozen_string_literal: true

require "test_helper"
require_relative "interpreter_helper"

# The exit: exit order, the configuration it leaves, and history recorded
# shallow and deep before any state leaves.
class ExitStatesTest < Minitest::Test
  include InterpreterHelper

  X = Statifier::Interpreter::ExitEntry

  HISTORY = <<~XML
    <state id="s" initial="c">
      <transition event="leave" target="out"/>
      <history id="h"><transition target="c"/></history>
      <history id="dh" type="deep"><transition target="c"/></history>
      <state id="c" initial="c1"><state id="c1"/><state id="c2"/></state>
      <parallel id="p">
        <state id="r1"><state id="x1"/><state id="x2"/></state>
        <state id="r2"><state id="y1"/><state id="y2"/></state>
      </parallel>
    </state>
    <state id="out"/>
    <state id="t" initial="t1"><history id="th"><transition target="t1"/></history><state id="t1"/></state>
  XML

  # The exit of s's leave transition with s and active active, and history.
  def leave(chart, *active, history: {})
    X.exit_states(snapshot(chart, "s", *active, history:), transitions_of(chart, "s"))
  end

  # The recorded history by history id, as ids.
  def recorded(chart, history) = history.to_h { |h, values| [chart.state(h).id, ids(chart, values)] }

  # sabotage: answer exit_set unreversed for states in ExitEntry.exit_states;
  # the assert_equal on the exit order fails.
  def test_states_exit_in_reverse_document_order_and_leave_the_configuration
    chart = machine(HISTORY)
    exited = leave(chart, "p", "r1", "x2", "r2", "y1")

    assert_equal %w[y1 r2 x2 r1 p s], ids(chart, exited.states)
    assert_equal ["scxml"], ids(chart, exited.configuration)
  end

  # sabotage: pass snapshot.with(configuration: snapshot.configuration -
  # exit_set) to record_history_values in ExitEntry.exit_states; the
  # assert_equal on c and c2 fails.
  # sabotage: test parent == index for both kinds in
  # ExitEntry.recorded_value; the assert_equal on dh fails.
  def test_shallow_records_active_children_and_deep_active_atomic_descendants_in_one_pass
    chart = machine(HISTORY)

    assert_equal({ "h" => ["c"], "dh" => ["c2"] }, recorded(chart, leave(chart, "c", "c2").history))
    assert_equal({ "h" => ["p"], "dh" => %w[x2 y1] },
                 recorded(chart, leave(chart, "p", "r1", "x2", "r2", "y1").history))
  end

  # sabotage: start the record from {} in place of snapshot.history.dup in
  # ExitEntry.record_history_values; the assert_equal loses th.
  def test_recording_overwrites_on_revisit_and_keeps_what_no_exit_touches
    chart = machine(HISTORY)
    exited = leave(chart, "c", "c1", history: { "h" => ["p"], "th" => ["t1"] })

    assert_equal({ "h" => ["c"], "th" => ["t1"], "dh" => ["c1"] }, recorded(chart, exited.history))
    assert_predicate exited.history, :frozen?
  end
end
