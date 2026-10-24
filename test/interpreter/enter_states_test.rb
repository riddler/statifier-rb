# frozen_string_literal: true

require "test_helper"
require_relative "interpreter_helper"

# The entry: entry order, the configuration it leaves, and the default-entry
# and history content each state's entry runs.
class EnterStatesTest < Minitest::Test
  include InterpreterHelper

  ENTRY = <<~XML
    <state id="a">
      <transition event="e" target="b"/><transition event="f" target="b2"/><transition event="g" target="h"/>
    </state>
    <state id="b"><initial><transition target="b1"/></initial><state id="b1"/><state id="b2"/></state>
    <state id="k" initial="k1"><history id="h"><transition target="k2"/></history><state id="k1"/><state id="k2"/></state>
  XML

  # The arrivals of a's transition at `position`, after its exit.
  def arrivals(chart, position, history: {})
    exit_then_enter(snapshot(chart, "a", history:), [transitions_of(chart, "a")[position]]).states
  end

  # sabotage: reduce over states_to_enter.reverse in ExitEntry.enter_states;
  # the assert_equal on the entry order fails.
  def test_states_enter_in_document_order_and_join_the_configuration
    chart = machine(ENTRY)
    entered = exit_then_enter(snapshot(chart, "a"), [transitions_of(chart, "a").first])

    assert_equal %w[b b1], ids(chart, entered.states.map(&:index))
    assert_equal %w[scxml b b1], ids(chart, entered.configuration)
  end

  # sabotage: answer machine.state(index).initial_transition whatever
  # default_entry says in ExitEntry.arrival; the second assert_equal fails.
  def test_the_initial_transition_s_content_runs_only_on_a_default_entry
    chart = machine(ENTRY)
    initial = chart.state(at(chart, "b")).initial_transition

    assert_equal [initial, nil], arrivals(chart, 0).map(&:initial_content)
    assert_equal [nil, nil], arrivals(chart, 1).map(&:initial_content)
  end

  # sabotage: answer nil for history_content in ExitEntry.arrival; the
  # assert_equal on k's arrival fails.
  def test_an_unrecorded_history_s_default_content_runs_on_its_parent
    chart = machine(ENTRY)

    assert_equal [chart.state(at(chart, "h")).history_default, nil], arrivals(chart, 2).map(&:history_content)
  end

  # sabotage: register the content when recorded is not nil in
  # Entering.enter_history_target; the assert_equal on nil fails.
  def test_a_recorded_history_restores_its_value_and_runs_no_default_content
    chart = machine(ENTRY)
    restored = arrivals(chart, 2, history: { "h" => ["k1"] })

    assert_equal [%w[k k1], [nil, nil]], [ids(chart, restored.map(&:index)), restored.map(&:history_content)]
  end
end
