# frozen_string_literal: true

require "test_helper"
require_relative "driver_helper"

# The driver's calls: what start, step, configuration and done? answer, the
# checks on what a host passes them, and the state as an immutable value.
class CallsTest < Minitest::Test
  include DriverHelper

  TWO = <<~XML
    <state id="a"><transition event="e.go" target="b"/></state>
    <final id="b"><donedata><param name="n" expr="7"/></donedata></final>
  XML

  # sabotage: answer `configuration` with the root left in (drop `- [0]` in
  # Calls.configuration); the assert_equal on the names fails.
  def test_start_enters_the_initial_states_and_answers_their_names_and_its_effects
    started = start(%(<state id="a"><state id="a1"/></state><state id="b"/>))

    assert_equal %w[a a1], active(started)
    assert_equal [E::DatamodelInit], started.effects.map(&:class)
    assert_predicate started.effects, :frozen?
  end

  # sabotage: answer `"?#{_1}"` for a state with no id in Calls.names; the
  # assert_equal on the names fails.
  def test_a_state_with_no_id_is_named_by_its_index
    assert_equal %w[#2 a], active(start(%(<parallel id="a"><state/></parallel>)))
  end

  # sabotage: drop the Routing.enqueue in Calls.step (drain the state as it
  # was); the assert_equal on the configuration fails.
  def test_step_takes_the_event_and_runs_the_chart_to_a_stable_configuration
    stepped = step(start(%(<state id="a"><transition event="e.go" target="b"/></state><state id="b"/>)), "e.go")

    assert_equal %w[b], active(stepped)
  end

  # sabotage: build the host's event without `data:` in Calls.step; the
  # assert_equal on the logged data fails.
  def test_step_carries_the_event_s_data
    started = start(%(<state id="a"><transition event="e.go"><log label="d" expr="_event.data"/></transition></state>))
    stepped = step(started, "e.go", data: { "k" => 1 })

    assert_equal [["d", { "k" => 1 }]], logs(stepped)
  end

  # sabotage: answer `done: true` for a running chart in Calls.done?; the
  # assert_equal on the running status fails.
  def test_done_answers_the_donedata_and_the_states_the_chart_stopped_in
    started = start(TWO)
    stopped = step(started, "e.go")
    status = Statifier.done?(stopped.state).value

    assert_equal [false, nil, nil], Statifier.done?(started.state).value.to_h.values
    assert_equal [true, { "n" => 7 }, %w[b], []], [status.done?, status.donedata, status.configuration, active(stopped)]
  end

  # sabotage: drop the `running` check in Calls.step; the assert_equal on the
  # error fails (the step is answered).
  def test_a_step_after_the_chart_stopped_is_refused
    stopped = step(start(TWO), "e.go")

    assert_equal [false, :not_running], [Statifier.step(stopped.state, "e.go").ok?,
                                         Statifier.step(stopped.state, "e.go").error]
  end

  # sabotage: drop `.freeze` on the external queue in Routing.enqueue; the
  # assert_predicate on the queue fails.
  def test_a_call_leaves_the_state_it_was_given_as_it_was_and_answers_a_frozen_one
    looping = %(<state id="a"><onentry><send event="again"/></onentry><transition event="again" target="a"/></state>)
    started = start(looping, max_macrostep_rounds: 2)
    stepped = step(started, "e.more")
    queues = [started, stepped].map { _1.state.external_queue.map(&:name) }

    assert_equal [%w[again], %w[again e.more]], queues
    assert_predicate stepped.state.external_queue, :frozen?
  end

  # sabotage: hand the host's datamodel to the loop as the default's frozen
  # copy (pass `datamodel: {}.freeze` in Calls.start); the assert_equal on the
  # logged value fails.
  def test_the_host_s_datamodel_is_read_and_never_frozen_in_place
    datamodel = { "x" => [1] }
    started = start(%(<state id="a"><onentry><log label="x" expr="x"/></onentry></state>), datamodel:)

    assert_equal [["x", [1]]], logs(started)
    refute_predicate datamodel, :frozen?
    refute_predicate datamodel["x"], :frozen?
  end

  # sabotage: drop the unknown-key check in Checks.start_options; the
  # assert_raises on the unknown option fails.
  def test_start_refuses_what_it_does_not_take
    chart = machine(%(<state id="a"/>))

    assert_raises(TypeError) { Statifier.start("<scxml/>") }
    assert_raises(ArgumentError) { Statifier.start(chart, routes: nil) }
    assert_raises(ArgumentError) { Statifier.start(chart, max_macrostep_rounds: 0) }
    assert_raises(TypeError) { Statifier.start(chart, session_id: 1) }
  end

  # sabotage: drop the `respond_to?(:deliver)` check in
  # Checks.registered_types; the first assert_raises fails.
  def test_start_refuses_processors_that_are_not_a_hash_of_types_to_processors
    chart = machine(%(<state id="a"/>))

    assert_raises(TypeError) { Statifier.start(chart, processors: { "x" => Object.new }) }
    assert_raises(TypeError) { Statifier.start(chart, processors: [["x", nil]]) }
    assert_raises(TypeError) { Statifier.start(chart, processors: { x: Object.new }) }
  end

  # sabotage: drop the `is_a?(State)` check in Checks.state; the
  # assert_raises on the configuration of a non-state fails.
  def test_the_reading_calls_refuse_what_is_not_a_driver_state
    assert_raises(TypeError) { Statifier.configuration({}) }
    assert_raises(TypeError) { Statifier.done?(nil) }
    assert_raises(TypeError) { Statifier.step(nil, "e") }
    assert_raises(TypeError) { Statifier.step(start(%(<state id="a"/>)).state, :e) }
  end

  # sabotage: merge `max_macrostep_rounds: MAX_MACROSTEP_ROUNDS` after the
  # host's options in Checks.start_options; the assert_equal on the budget
  # fails.
  def test_the_round_budget_and_the_trace_flag_are_the_host_s
    started = start(%(<state id="a"/>), max_macrostep_rounds: :infinity, trace: true)

    assert_equal :infinity, started.state.machine_state.max_macrostep_rounds
    assert_includes started.effects.map(&:class), T::MacrostepStable
  end

  # sabotage: answer `order = state.configuration.freeze` (ascending) in
  # Stop.exit_interpreter; the assert_equal on the exit order fails.
  def test_the_stop_leaves_every_state_in_reverse_document_order
    stopped = moved(Statifier.start(machine(<<~XML), trace: true))
      <parallel id="p"><state id="x"><transition target="f"/></state><state id="y"/></parallel>
      <final id="f"/>
    XML
    exits = stopped.effects.grep(T::ExitSet).map(&:indexes)

    assert_equal [4, 0], exits.last
    assert_equal [3, 2, 1], exits.first
  end

  # sabotage: drop `warnings: validated.warnings` in Statifier.chart; the
  # assert_equal on the warning reasons fails.
  def test_a_host_reads_the_compile_warnings_on_the_machine
    body = %(<state id="s"><invoke><finalize><raise event="e"/></finalize></invoke></state>)
    compiled = Statifier.compile(%(<scxml #{ROOT}>#{body}</scxml>))

    assert_equal [:finalize_forbidden_content], compiled.value.warnings.map(&:reason)
    assert_equal ["<raise> must not occur inside <finalize>"], compiled.value.warnings.map(&:message)
  end
end
