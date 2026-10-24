# frozen_string_literal: true

require "test_helper"
require_relative "invoke_helper"

# The interpreter's other invoke passes: the cancel of a state's live
# invocations as it exits or the chart stops, and the finalize and
# autoforward pass before an external event's selection.
class InvokeExitTest < Minitest::Test
  include LoopInvokeHelper

  EXITING = <<~XML.freeze
    <state id="a">
      <invoke id="c">#{CHILD}</invoke><invoke id="other" type="other"/>
      <onexit><log label="out"/></onexit>
      <transition event="e.go" target="b"/>
    </state>
    <state id="b"/>
  XML

  FINALIZE = <<~XML.freeze
    <state id="a">
      <invoke id="c">#{CHILD}<finalize><log label="fin" expr="_event.name"/></finalize></invoke>
      <transition event="r"><log label="took" expr="_event.invokeid"/></transition>
    </state>
  XML

  EMPTY_FINALIZE = <<~XML
    <datamodel><data id="w" expr="0"/><data id="z" expr="0"/></datamodel>
    <state id="a"><invoke id="c"><param name="w" location="w"/><param name="z" location="z"/><finalize/></invoke></state>
  XML

  # sabotage: drop the `Invoke::Passes.cancel_invocations` step from
  # Step.depart; the assert_equal on the effect kinds fails.
  def test_a_state_that_exits_cancels_its_live_invocations_after_its_onexit
    handled = handle(start(EXITING), "e.go")
    cancels = handled.effects.grep(E::CancelInvoke).map { [_1.invoke_id, _1.state_index] }

    assert_equal %w[Log CancelInvoke], kinds(handled.effects).grep(/\A(Log|CancelInvoke)\z/)
    assert_equal [["c", 1]], cancels
    assert_empty handled.state.active_invocations
  end

  # sabotage: drop the `Invoke::Passes.cancel_invocations` step from
  # Stop.leave; the assert_equal on the cancelled ids fails.
  def test_the_chart_stopping_cancels_the_invocations_still_live
    cancelled = L.cancel(start(%(<state id="a"><invoke id="c">#{CHILD}</invoke></state>)).state)

    assert_equal [%w[c], :done], [cancelled.effects.grep(E::CancelInvoke).map(&:invoke_id), cancelled.state.status]
    assert_equal :not_running, L.cancel(cancelled.state).error
  end

  # sabotage: compare `invoke_id != event.invokeid` in Passes.pass_one;
  # the assert_equal on the logs fails.
  def test_an_event_from_the_invocation_runs_its_finalize_before_the_selection
    started = start(FINALIZE)

    assert_equal [%w[fin r], %w[took c]], pairs(handle(started, EV.external("r", invokeid: "c")).effects)
    assert_equal [["took", Predicator::UNDEFINED]], pairs(handle(started, "r").effects)
  end

  # sabotage: answer `none(state)` for an empty block in Passes.finalize;
  # the assert_equal on the datamodel fails.
  def test_an_empty_finalize_writes_the_named_values_back
    handled = handle(start(EMPTY_FINALIZE), EV.external("r", invokeid: "c", data: { "w" => 9, "q" => 1 }))
    change = handled.effects.grep(E::DatamodelChange).first

    assert_equal [9, 0], handled.state.datamodel.values_at("w", "z")
    assert_equal [["w"], 9, 0, { kind: :finalize, state_index: 1, invoke_index: 0 }],
                 change.to_h.values_at(:location_path, :new_value, :prior_value, :owner)
  end

  # sabotage: answer `[]` from Passes.forward whatever `autoforward`; the
  # assert_equal on the forwarded event fails.
  def test_an_autoforwarding_invocation_is_forwarded_the_event_whole_with_the_trace_last
    started = start(%(<state id="a"><invoke id="c" autoforward="true">#{CHILD}</invoke></state>), trace: true)
    event = EV.external("e.go", data: 3, sendid: "x")
    effects = handle(started, event).effects
    trace = effects.grep(T::FinalizeAutoforward).first
    forwards = effects.grep(E::Autoforward).map { [_1.invoke_id, _1.state_index, _1.event] }

    assert_equal [["c", 1, event]], forwards
    assert_equal [[], %w[c]], [trace.finalized, trace.forwarded]
  end
end
