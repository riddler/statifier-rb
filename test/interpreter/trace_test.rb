# frozen_string_literal: true

require "test_helper"
require_relative "loop_helper"

# The trace effects, in the reference's order and with its stamps, and
# none at all for a state that does not trace.
class TraceTest < Minitest::Test
  include LoopHelper

  CHART = <<~XML
    <datamodel><data id="x" expr="1"/></datamodel>
    <state id="a"><transition event="e.go" cond="x == 1" target="b"/></state>
    <state id="b"><onentry><log label="b"/></onentry></state>
  XML

  # sabotage: answer `trace = []` for the ExitSet in Step.exit_states; the
  # assert_equal on the kinds fails.
  def test_an_external_event_answers_the_reference_trace_order_and_stamps
    handled = handle(start(CHART, trace: true), "e.go")

    assert_equal %w[T.EventDequeued T.FinalizeAutoforward T.CondsEvaluated T.TransitionsSelected T.ExitSet
                    T.ContentExecuted T.EntrySet Log T.ContentExecuted T.TransitionsSelected T.InvokePass
                    T.MacrostepStable], kinds(handled.effects)
    assert_equal(([[2, 0, 0]] * 4) + ([[2, 1, 0]] * 5) + ([[2, 1, 1]] * 3),
                 handled.effects.map { [_1.macrostep, _1.microstep, _1.round] })
  end

  # sabotage: answer `:disabled` for a true value in Selection.evaluation;
  # the assert_equal fails.
  def test_conds_evaluated_names_each_written_condition_and_its_outcome
    handled = handle(start(CHART, trace: true), "e.go")

    assert_equal [{ t_index: 0, outcome: :enabled, reason: nil }],
                 handled.effects.grep(T::CondsEvaluated).first.evaluations
  end

  # sabotage: answer `[klass.new(**fields, **state.counters)]` whatever
  # state.trace says in Blocks.traced; the assert_equal fails.
  def test_a_state_that_does_not_trace_answers_only_the_effects_that_are_not_traces
    traced = handle(start(CHART, trace: true), "e.go").effects
    plain = handle(start(CHART), "e.go").effects

    assert_equal traced.reject { _1.class.name.include?("::Trace::") }, plain
  end

  # sabotage: answer `state` unchanged in place of the cleared one from
  # Macrostep.invoke_pass; the assert_equal fails, as the second pass names a
  # again.
  def test_the_invoke_pass_names_the_states_entered_since_the_last_pass
    handled = handle(start(CHART, trace: true), "e.go")
    started = start(CHART, trace: true)

    assert_equal([[0, 1], [2]], [started, handled].map { _1.effects.grep(T::InvokePass).first.state_indexes })
  end

  # sabotage: stamp the TransitionsSelected from `state.begin_microstep` in
  # Macrostep.run_selected; the assert_equal fails (microstep 1).
  def test_a_selection_trace_carries_the_microstep_it_ran_in
    selected = handle(start(CHART, trace: true), "e.go").effects.grep(T::TransitionsSelected).first

    assert_equal [[0], 0], [selected.t_indexes, selected.microstep]
  end

  # sabotage: build the trace from `fields` as given (drop the
  # transform_values) in Blocks.traced; the assert fails, as the invoke
  # pass's empty list and the block owners are not frozen.
  def test_every_trace_effect_is_deeply_frozen
    effects = handle(start(CHART, trace: true), "e.go").effects

    assert(effects.all? { Ractor.shareable?(_1) })
  end
end
