# frozen_string_literal: true

require "test_helper"
require_relative "loop_helper"

# What a microstep runs on the way out and in: late binding, initial and
# history content, completion events with their donedata, and the stop at
# a top-level final.
class StepTest < Minitest::Test
  include LoopHelper

  # sabotage: drop the `return ... if state.entered_states.include?(index)`
  # line in Step.enter; the assert_equal on the changes fails, as b's data
  # binds twice.
  def test_late_binding_binds_a_states_own_data_on_its_first_entry_only
    stepped = start(<<~XML, %(#{ROOT} binding="late"))
      <state id="a"><transition event="e.go" target="b"/></state>
      <state id="b"><datamodel><data id="y" expr="5"/></datamodel><transition event="e.go" target="a"/></state>
    XML
    changes = %w[e.go e.go e.go].reduce([stepped]) { |acc, name| acc << handle(acc.last, name) }
                                .map { _1.effects.grep(E::DatamodelChange).map(&:new_value) }

    assert_equal [[], [5], [], []], changes
  end

  # sabotage: drop `arrival.initial_content` from the content list in
  # Step.arrive; the assert_equal on the logs fails.
  def test_initial_content_and_default_history_content_run_after_onentry
    started = start(<<~XML)
      <state id="p"><onentry><log label="p"/></onentry>
        <initial><transition target="h"><log label="initial"/></transition></initial>
        <history id="h"><transition target="c"><log label="history"/></transition></history>
        <state id="c"><onentry><log label="c"/></onentry></state>
      </state>
    XML

    assert_equal [["p", nil], ["initial", nil], ["history", nil], ["c", nil]], logs(started.effects)
  end

  # sabotage: raise the parent completion with no data in Step.complete;
  # the assert_equal on the logged data fails.
  def test_a_final_child_raises_its_parents_done_event_carrying_its_donedata
    started = start(<<~XML, trace: true)
      <datamodel><data id="x" expr="3"/></datamodel>
      <state id="p"><final id="f"><donedata><param name="v" expr="x"/><param name="w" expr="nope"/></donedata></final>
        <transition event="done.state.p" target="q"><log label="data" expr="_event.data"/></transition></state>
      <state id="q"/>
    XML
    dequeued = started.effects.grep(T::EventDequeued).map(&:event)

    assert_equal [["data", { "v" => 3 }]], logs(started.effects)
    assert_equal([["error.execution", { kind: :donedata_param, state_index: 2, param_index: 1 }],
                  ["done.state.p", { kind: :state, state_index: 2 }]], dequeued.map { [_1.name, _1.cause.origin] })
  end

  # sabotage: answer [] from ExitEntry.parallel_completion; the assert_equal
  # fails (the parallel's event is never raised).
  def test_a_parallel_whose_regions_are_all_final_raises_its_own_done_event
    started = start(<<~XML)
      <parallel id="p">
        <state id="r1"><final id="f1"/></state><state id="r2"><final id="f2"/></state>
        <transition event="done.state.p" target="done"/>
      </parallel>
      <state id="done"/>
    XML

    assert_equal %w[done], active(started.state)
  end

  # sabotage: answer [state, nil] for a <content> body in
  # Blocks.donedata_content; the assert_equal on the donedata fails.
  def test_a_top_level_final_stops_the_chart_with_its_donedata_last
    started = start(<<~XML)
      <state id="a"><onexit><log label="bye"/></onexit><transition event="e.go" target="f"/></state>
      <final id="f"><onexit><log label="final"/></onexit><donedata><content>[1, 2]</content></donedata></final>
    XML
    handled = handle(started, "e.go")
    done = handled.effects.last

    assert_equal [["bye", nil], ["final", nil]], logs(handled.effects)
    assert_equal [[1, 2], nil, [0, 2]], [done.donedata, done.donedata_error, done.configuration]
    assert_equal [:done, false, [], []],
                 handled.state.to_h.values_at(:status, :running, :configuration, :internal_queue)
  end

  # sabotage: answer [data, nil, state] from Stop.collect_donedata; the
  # assert_equal on the error's kind fails.
  def test_a_donedata_that_fails_answers_its_error_and_no_data
    done = start(%(<final id="f"><donedata><content expr="nope.a"/></donedata></final>)).effects.last

    assert_same Predicator::UNDEFINED, done.donedata
    assert_equal "evaluator_error", done.donedata_error&.dig("kind")
  end

  # sabotage: answer `donedata = nil` for every state (skip the
  # top_level_final? branch) in Stop.leave; the assert_equal fails.
  def test_a_top_level_final_with_no_donedata_answers_no_data
    started = start(%(<state id="a"><onentry><raise event="e"/></onentry><transition event="e" target="f"/></state>
                      <final id="f"/>))

    assert_equal [Predicator::UNDEFINED, nil], started.effects.last.to_h.values_at(:donedata, :donedata_error)
  end

  # sabotage: answer `configuration: state.configuration` in Step.join;
  # the assert_equal on the In() logs fails.
  def test_an_entering_states_onentry_sees_itself_and_its_ancestors_active
    started = start(%(<state id="p"><state id="c"><onentry><log label="in" expr="[In('p'), In('c')]"/></onentry>
                      </state></state>))

    assert_equal [["in", [true, true]]], logs(started.effects)
  end
end
