# frozen_string_literal: true

require_relative "position_helper"

# Position import: a state imported back in holds the position and steps as
# the original does, the driver's own members start afresh, and each
# refusal.
class PositionImportTest < Minitest::Test
  include PositionHelper

  # sabotage: leave the root out of the imported configuration (return
  # `indexes` from Rebuild.rooted); the assert_equal on the configuration
  # fails.
  def test_an_imported_state_holds_the_original_s_position_and_steps_as_it_does
    original = after("e.go")
    state = imported(original)

    assert_equal original.machine_state.configuration, state.machine_state.configuration
    assert_equal position(original), position(state)
    assert_equal %w[a a1], Statifier.configuration(moved(Statifier.step(state, "e.go")).state).value
  end

  # sabotage: decode the datamodel as the position's text, undecoded, in
  # Text.decode; the assert_equal on the count fails.
  def test_an_imported_state_keeps_the_datamodel
    state = imported(after("e.go"))
    stepped = moved(Statifier.step(state, "e.go")).state

    assert_equal 2, stepped.machine_state.datamodel["n"]
  end

  # sabotage: import the history as empty in Rebuild.machine_state; the
  # assert_equal on the configuration fails (a1, the default, is entered).
  def test_an_imported_state_keeps_the_recorded_history
    state = imported(after("e.go", "e.out"))
    back = moved(Statifier.step(state, "e.back")).state

    assert_equal %w[a a2], Statifier.configuration(back).value
  end

  # sabotage: start the imported clock at 1 in Rebuild.state; the
  # assert_equal on the driver's members fails.
  def test_an_imported_state_starts_the_driver_s_members_afresh_with_the_position_s_session_id
    state = imported(after("e.go", session_id: "s-other"))

    assert_equal [0, [], [], {}, nil, nil, "s-other"],
                 [state.now_ms, state.timers, state.external_queue, state.held_sends, state.halted, state.done,
                  state.session_id]
  end

  # sabotage: declare no send type to the interpreter (`send_types: nil`
  # in Rebuild.sends); the assert_equal on the delivery fails.
  def test_an_import_registers_the_processors_the_host_passes
    recorder = Recorder.new
    processors = { "x" => recorder }
    chart = %(<state id="a"><transition event="e.go"><send type="x" event="out"/></transition></state>)
    exported = through_json(position(start(chart, processors:).state))
    state = moved(Statifier.import_position(machine(chart), exported, processors:))
    step(Statifier::Driver::Moved.new(state:, effects: []), "e.go", processors:)

    assert_equal(%w[out], recorder.calls.map { _1[2].name })
  end

  # sabotage: register no type on import (pass `{}` to registered_types in
  # Position.import); the assert_raises on the step fails.
  def test_an_imported_state_refuses_processors_of_other_types
    chart = %(<state id="a"/>)
    exported = through_json(position(start(chart, processors: { "x" => Recorder.new }).state))
    state = moved(Statifier.import_position(machine(chart), exported, processors: { "x" => Recorder.new }))

    assert_raises(ArgumentError) { Statifier.step(state, "e.go") }
  end

  # sabotage: build no done record in Rebuild.done; the assert_equal on
  # the status fails.
  def test_a_stopped_position_imports_stopped
    state = imported(after("e.out", "e.end"))
    status = Statifier.done?(state).value

    assert_equal [true, Predicator::UNDEFINED, []], [status.done?, status.donedata, status.configuration]
    assert_equal :not_running, Statifier.step(state, "e.go").error
  end

  # sabotage: import the invoke counter as 0 in Rebuild.fields; the
  # assert_equal on the exported position fails.
  def test_the_live_invocations_and_the_invoke_counter_travel_out_and_back
    exported = through_json(position(after))
    exported["active_invocations"] = [{ "state" => "a", "invoke_index" => 0, "invoke_id" => "a.i1" }]
    exported["invoke_counter"] = 4
    state = moved(Statifier.import_position(machine(CHART), exported))

    assert_equal exported, position(state)
  end

  # sabotage: read the identity in Shape.failure (refuse a key not in
  # KEYS); the assert on the import fails.
  def test_an_import_ignores_a_key_that_is_not_required
    exported = through_json(position(after)).merge("identity" => { "content_hash" => "sha256:0" })

    assert_predicate Statifier.import_position(machine(CHART), exported), :ok?
  end

  # sabotage: freeze the host's ids in place (`ids.each(&:freeze)` in
  # Rebuild.indexes); the refute_predicate on the host's id fails.
  def test_an_import_freezes_nothing_the_host_passes
    exported = through_json(position(after))
    moved(Statifier.import_position(machine(CHART), exported))

    refute_predicate exported, :frozen?
    refute_predicate exported["configuration"].first, :frozen?
  end
end
