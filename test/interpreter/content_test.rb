# frozen_string_literal: true

require "test_helper"
require_relative "content_helper"

# The block runner: one context threaded through the block, the first
# failure stopping it as error.execution, and raise, log, assign, if and
# script, each with its failures.
class ContentTest < Minitest::Test
  include ContentHelper

  # sabotage: build the Event with name "x" in Content.raise_event; the
  # assert_equal on the names fails.
  def test_raise_queues_an_internal_event_naming_its_node
    outcome = run_block(%(<raise event="e.one"/><raise event="e.two"/>))

    assert_equal([["e.one", :internal, origin(0)], ["e.two", :internal, origin(1)]],
                 outcome.raised.map { [_1.name, _1.type, _1.cause.origin] })
  end

  # sabotage: pass value: nil to Effect::Log.new in Content.log; the
  # assert_equal on the effects fails.
  def test_log_answers_its_label_and_value_with_the_counters
    outcome = run_block(%(<log label="l1" expr="x + 1"/><log label="only"/>))
    fields = { owner: OWNER, macrostep: 2, microstep: 3, round: 4 }

    assert_equal [E::Log.new(label: "l1", value: 2, c_index: 0, **fields),
                  E::Log.new(label: "only", value: nil, c_index: 1, **fields)], outcome.effects
  end

  # sabotage: drop the `return [run, evaluated.error] unless evaluated.ok?`
  # guard in Content.log; the assert_equal on the effects fails, as a log of
  # the failure is answered.
  def test_a_log_whose_expr_fails_stops_the_block_with_error_execution
    outcome = run_block(%(<log expr="1"/><log expr="nope"/><raise event="never"/>))

    assert_equal [1], outcome.effects.map(&:value)
    assert_equal([["error.execution", origin(1)]], outcome.raised.map { [_1.name, _1.cause.origin] })
    assert_equal "evaluator_error", outcome.raised.first.data["kind"]
  end

  # sabotage: pass new_value: nil to Content.change in Content.assign; the
  # assert_equal on the change fails.
  def test_assign_writes_the_location_and_answers_the_change
    outcome = run_block(%(<assign location="m.b" expr="[x]"/><assign location="x" expr="x * 5"/><log expr="m.b"/>))
    change = outcome.effects.first

    assert_equal [%w[m b], "m.b", [1], Predicator::UNDEFINED, 0],
                 [change.location_path, change.location_source, change.new_value, change.prior_value, change.c_index]
    assert_equal 5, outcome.context.data["x"]
    assert_equal [[1]], effects_of(outcome, E::Log).map(&:value)
  end

  # sabotage: answer [run, nil] in place of [run, written.error] in
  # Content.assign; the assert_equal on the raised names fails.
  def test_an_assign_to_an_undeclared_root_stops_the_block
    outcome = run_block(%(<raise event="a"/><assign location="zz" expr="1"/><raise event="b"/>))

    assert_equal %w[a error.execution], raised_names(outcome)
    assert_equal rv(DM::UnboundLocation.new(location: "zz")), outcome.raised.last.data
    refute outcome.context.data.key?("zz")
    assert_equal [0, 1], outcome.executed
  end

  # sabotage: drop `&& evaluated.value` from Content.if_node; the
  # assert_equal on the raised names fails, as the false branch runs.
  def test_if_runs_the_first_branch_whose_condition_holds
    outcome = run_block(<<~XML)
      <if cond="x == 2"><raise event="one"/><elseif cond="x == 1"/><raise event="two"/><else/><raise event="three"/></if>
    XML

    assert_equal ["two"], raised_names(outcome)
  end

  # sabotage: add `&& !branch.cond.nil?` to the nested(...) line of
  # Content.if_node; the assert_equal on the log fails.
  def test_else_runs_when_no_condition_holds_and_its_writes_reach_later_nodes
    outcome = run_block(%(<if cond="false"><raise event="one"/><else/><assign location="x" expr="7"/></if>) +
                        %(<log expr="x"/>))

    assert_equal [7], effects_of(outcome, E::Log).map(&:value)
  end

  # sabotage: skip run.defer in Content.if_node; the assert_equal on the
  # raised names fails, as no error.execution follows.
  def test_a_failing_condition_is_passed_over_and_raised_after_the_if
    outcome = run_block(<<~XML)
      <if cond="nope"><raise event="one"/><elseif cond="5"/><raise event="two"/><else/><raise event="three"/></if>
      <raise event="after"/>
    XML

    assert_equal %w[three error.execution error.execution after], raised_names(outcome)
    assert_equal [origin(0), rv(DM::NonBooleanCond.new(value: 5))], origin_and_data(outcome.raised[2])
    assert_equal origin(0), outcome.raised[1].cause.origin
  end

  # sabotage: answer [after, reason] in place of [after.with(effects:
  # run.effects), reason] in Content.execute_node; the assert_equal on the
  # effect classes fails, as the failed if's log and change are kept.
  def test_a_failure_inside_an_if_names_the_inner_node_drops_its_effects_and_keeps_its_writes
    outcome = run_block(<<~XML)
      <log expr="1"/><if cond="true"><log expr="2"/><raise event="in"/><assign location="x" expr="3"/>
      <assign location="zz" expr="1"/><raise event="never"/></if><raise event="never2"/>
    XML

    assert_equal [E::Log], outcome.effects.map(&:class)
    assert_equal [%w[in error.execution], 3], [raised_names(outcome), outcome.context.data["x"]]
    assert_equal [origin(1), rv(nested_at(5))], origin_and_data(outcome.raised.last)
  end

  # sabotage: answer [run, reason] unwrapped in Content.nested; the
  # assert_equal on the reason fails.
  def test_a_nested_if_failure_wraps_each_level
    outcome = run_block(%(<if cond="true"><if cond="true"><assign location="zz" expr="0"/></if></if>))
    inner = C::NestedContent.new(c_index: 2, reason: DM::UnboundLocation.new(location: "zz"))

    assert_equal rv(C::NestedContent.new(c_index: 1, reason: inner)), outcome.raised.last.data
  end

  # sabotage: drop `break ran if failed` in Content.execute_block; the
  # assert_equal on executed fails.
  def test_the_block_stops_at_the_first_failure_and_names_what_ran
    outcome = run_block(%(<log expr="1"/><log expr="nope"/><log expr="3"/>))

    assert_equal [0, 1], outcome.executed
    assert_equal [1], outcome.effects.map(&:value)
  end

  # sabotage: start the Run with sends: Send::SendState::INITIAL in
  # Content.execute_block; the assert_equal fails on the send state.
  def test_an_empty_block_answers_what_it_was_given
    chart = content_machine("")
    data = bound(chart)
    sends = Internals::Interpreter::Send::SendState::INITIAL.with(send_counter: 4, timer_counter: 2)
    outcome = C.execute_block(DM.context(data, chart, [0, 1]), [], stamp, sends)

    assert_equal [[], [], [], data, sends],
                 [outcome.effects, outcome.raised, outcome.executed, outcome.context.data, outcome.sends]
  end

  # sabotage: start the Run with context.with(configuration: [0]) in
  # Content.execute_block; In('a') answers false and the assert_equal fails.
  def test_in_reads_the_configuration_the_block_runs_under
    outcome = run_block(%(<log expr="In('a')"/>))

    assert_equal [true], outcome.effects.map(&:value)
  end

  # sabotage: drop .freeze from Selection.get_effective_target_states; the
  # assert_predicate fails.
  def test_the_effective_target_states_are_frozen
    chart = machine(%(<state id="a"><transition event="e" target="b"/></state><state id="b"/>))
    t = chart.transitions.first

    assert_predicate I::Selection.get_effective_target_states(snapshot(chart, "a"), t), :frozen?
  end
end
