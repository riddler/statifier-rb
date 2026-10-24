# frozen_string_literal: true

require "test_helper"
require_relative "interpreter_helper"

# The completion events entry raises: a final state's parent's, a
# completed parallel's after its last region's, and none for a top-level
# final, which stops the execution.
class CompletionTest < Minitest::Test
  include InterpreterHelper

  X = Internals::Interpreter::ExitEntry

  CHART = <<~XML
    <state id="go">
      <transition event="both" target="af bf"/><transition event="one" target="af"/><transition event="top" target="end"/>
      <transition event="in" target="cf"/>
    </state>
    <parallel id="p">
      <state id="r1"><state id="a"/><final id="af"><donedata><param name="v" expr="1"/></donedata></final></state>
      <state id="r2"><state id="b"/><final id="bf"/></state>
    </parallel>
    <state id="c"><state id="c1"/><final id="cf"/></state>
    <final id="end"/>
  XML

  # The arrivals of go's transition at `position` from the active ids.
  def arrivals(chart, position, *active)
    exit_then_enter(snapshot(chart, *active), [transitions_of(chart, "go")[position]]).states
  end

  # Each arrival that raises a completion, by id, with its completions.
  def completions(chart, position, *active)
    raising = arrivals(chart, position, *active).reject { _1.completions.empty? }
    raising.map { |arrival| [chart.state(arrival.index).id, arrival.completions.map(&:to_h)] }
  end

  # The completion of `name` that entering the final state `final` raises.
  def done(chart, name, final, donedata: true) = { name: "done.state.#{name}", final: at(chart, final), donedata: }

  # sabotage: drop the parent_event from the list in
  # ExitEntry.completion_events; the assert_equal fails.
  def test_entering_a_final_in_a_compound_raises_its_parent_s_completion_with_donedata
    chart = machine(CHART)

    assert_equal [["cf", [done(chart, "c", "cf")]]], completions(chart, 3, "go")
  end

  # sabotage: build entered from config without index
  # (snapshot.with(configuration: config)) in ExitEntry.enter_states; the
  # assert_equal on done.state.p fails.
  def test_completing_the_last_region_raises_the_parallel_s_completion_after_the_region_s
    chart = machine(CHART)
    last = [done(chart, "r2", "bf"), done(chart, "p", "bf", donedata: false)]

    assert_equal [["af", [done(chart, "r1", "af")]], ["bf", last]], completions(chart, 0, "go")
  end

  # sabotage: use any? in place of all? for a parallel in
  # ExitEntry.parallel_completion; the assert_equal gains done.state.p.
  def test_completing_one_region_only_raises_only_the_region_s_completion
    chart = machine(CHART)

    assert_equal [["af", [done(chart, "r1", "af")]]], completions(chart, 1, "p", "r2", "b")
  end

  # sabotage: answer stops: false in ExitEntry.arrival; the assert on stops
  # fails.
  def test_entering_a_top_level_final_stops_the_execution_and_raises_nothing
    arrival = arrivals(machine(CHART), 2, "go").first

    assert arrival.stops
    assert_empty arrival.completions
  end

  # The chart with the state id's id removed, as no validated chart has it.
  def unnamed(chart, id)
    index = at(chart, id)
    chart.with(states: chart.states.map { _1.index == index ? _1.with(id: nil) : _1 })
  end

  # sabotage: answer true from ExitEntry.named?; the assert_empty fails on a
  # "done.state." event with no id.
  def test_a_parent_with_no_id_raises_nothing_and_a_parallel_with_no_id_nothing_for_itself
    chart = machine(CHART)
    active = %w[p r1 af r2 bf]
    no_parent = X.completion_events(snapshot(unnamed(chart, "r2"), *active), at(chart, "bf"))
    no_parallel = X.completion_events(snapshot(unnamed(chart, "p"), *active), at(chart, "bf"))

    assert_empty no_parent
    assert_equal [done(chart, "r2", "bf")], no_parallel.map(&:to_h)
  end

  # sabotage: answer true in the else arm of ExitEntry.in_final_state?; the
  # refute on the final itself fails.
  def test_in_final_state
    chart = machine(CHART)
    region_done = snapshot(chart, "p", "r1", "af", "r2", "b")
    all_done = snapshot(chart, "p", "r1", "af", "r2", "bf")
    answers = [[region_done, "r1"], [region_done, "r2"], [region_done, "p"], [all_done, "p"], [all_done, "af"]]

    assert_equal([true, false, false, true, false], answers.map { |snap, id| X.in_final_state?(snap, at(chart, id)) })
  end
end
