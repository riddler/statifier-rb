# frozen_string_literal: true

require "test_helper"
require_relative "loop_helper"

# The interpreter's loop: starting a chart, taking an external event,
# delivering an internal one, the macrostep and its round budget, the
# counters, and stopping at a top-level final.
class LoopTest < Minitest::Test
  include LoopHelper

  ROUND_TRIP = <<~XML
    <datamodel><data id="x" expr="1"/></datamodel>
    <state id="a">
      <onexit><log label="exit" expr="In('a')"/></onexit>
      <transition event="e.go" target="b"><log label="move" expr="x"/></transition>
    </state>
    <state id="b"><onentry><log label="enter" expr="In('b')"/></onentry></state>
  XML

  # sabotage: drop `.begin_microstep` from Loop.initialize; the
  # assert_equal on the counters fails (microstep 0).
  def test_start_answers_the_datamodel_first_and_enters_the_initial_states_as_macrostep_one
    started = start(ROUND_TRIP)

    init, change = started.effects

    assert_equal [%w[a], true], [active(started.state), started.state.running]
    assert_equal [E::DatamodelInit, [1, 1, 0]], [init.class, [init.macrostep, init.microstep, init.round]]
    assert_equal [["x"], 0, 1, 1, 0], change.to_h.values_at(:location_path, :d_index, :new_value, :macrostep, :round)
  end

  # sabotage: answer `executed.then_step(exited)` in place of
  # `exited.then_step(executed)` in Step.microstep; the assert_equal on the
  # logs fails.
  def test_an_event_exits_runs_the_transition_then_enters_each_block_seeing_its_own_state_active
    handled = handle(start(ROUND_TRIP), "e.go")

    assert_equal [["exit", true], ["move", 1], ["enter", true]], logs(handled.effects)
    assert_equal %w[b], active(handled.state)
    assert_equal [2, 1], [handled.state.macrostep, handled.state.microstep]
  end

  # sabotage: answer `transitions.empty? ? :selected : :none` in
  # Loop.take; the assert_equal fails.
  def test_last_selection_says_whether_the_event_selected_a_transition
    started = start(ROUND_TRIP)

    selections = [handle(started, "e.other"), handle(started, "e.go")].map { _1.state.last_selection }

    assert_nil started.state.last_selection
    assert_equal %i[none selected], selections
  end

  # sabotage: drop `.put_event(event)` in Loop.handle_event; the
  # assert_equal on the logged event fails.
  def test_the_external_event_is_underscore_event_while_it_is_handled
    stepped = start(<<~XML)
      <state id="a"><transition event="e.go" target="b"><log label="ev" expr="[_event.name, _event.type, _event.data]"/></transition></state>
      <state id="b"/>
    XML

    assert_equal [["ev", ["e.go", "external", 7]]], logs(handle(stepped, EV.external("e.go", data: 7)).effects)
  end

  # sabotage: drop the Ractor.make_shareable around the put_event in
  # MachineState#put_event; the assert fails, as the event's type text is
  # not frozen and an event that selects nothing runs no block to freeze it.
  def test_the_datamodel_stays_deeply_frozen_once_an_event_is_set
    stepped = start(%(<state id="a"><transition event="e.go" target="b"/></state><state id="b"/>))

    assert Ractor.shareable?(handle(stepped, EV.external("e.none", data: [1])).state.datamodel)
  end

  # sabotage: answer `[true, head.then_step(...)]` in
  # Macrostep.internal_round; the assert_equal on the invoke passes fails,
  # as the macrostep ends after the first event and the loop re-enters.
  def test_raised_events_are_taken_in_order_within_one_macrostep
    started = start(<<~XML, trace: true)
      <state id="a"><onentry><raise event="one"/><raise event="two"/></onentry>
        <transition event="one" target="b"/></state>
      <state id="b"><transition event="two" target="c"/></state>
      <state id="c"/>
    XML

    assert_equal [%w[c], [], 1], [active(started.state), started.state.internal_queue, started.state.macrostep]
    assert_equal 1, started.effects.grep(T::InvokePass).size
  end

  # sabotage: drop the `unless executed.ok?` raise in
  # Loop.run_global_scripts; the assert_equal on the configuration fails.
  def test_a_global_script_runs_before_entry_and_a_failing_one_raises_error_execution
    started = start(<<~XML)
      <datamodel><data id="x" expr="1"/></datamodel>
      <script>x = x + 1</script><script>nope = nope + 1</script>
      <state id="a"><onentry><log label="x" expr="x"/></onentry><transition event="error.execution" target="b"/></state>
      <state id="b"/>
    XML

    assert_equal [["x", 2]], logs(started.effects)
    assert_equal %w[b], active(started.state)
  end

  # sabotage: answer `Handled.new(state:, effects: [], error: nil)` for a
  # stopped chart in Loop.handle_event; the assert_equal fails.
  def test_a_stopped_chart_refuses_an_event_and_an_internal_delivery
    stopped = start(%(<final id="f"/>)).state

    assert_equal %i[not_running not_running],
                 [L.handle_event(stopped, EV.external("e")).error,
                  L.deliver_internal(stopped, :internal, "e", { kind: :state, state_index: 0 }).error]
  end

  # The origin a driver names for an event it delivers.
  ORIGIN = { kind: :content, c_index: 9, owner: { kind: :transition, t_index: 0 } }.freeze

  # sabotage: call raise_platform for both kinds in Loop.deliver_internal;
  # the assert_equal on the types fails.
  def test_deliver_internal_queues_one_event_of_its_kind_and_runs_the_macrostep
    started = start(<<~XML, trace: true)
      <state id="a"><transition event="e.in" target="b"/></state><state id="b"><transition event="e.pf" target="c"/></state>
      <state id="c"/>
    XML
    first = L.deliver_internal(started.state, :internal, "e.in", ORIGIN, data: 1, sendid: "s1")
    second = L.deliver_internal(first.state, :platform, "e.pf", ORIGIN)

    assert_equal([["e.in", :internal, 1, "s1", ORIGIN], ["e.pf", :platform, Predicator::UNDEFINED, nil, ORIGIN]],
                 dequeued(first.effects + second.effects))
    assert_equal %w[c], active(second.state)
  end

  # sabotage: stamp `caller_context: nil` in Loop.handle_event; the
  # assert_same fails.
  def test_the_events_caller_context_is_read_from_the_state_by_a_delayed_send
    context = +"host value"
    stepped = start(%(<state id="a"><transition event="e.go"><send event="later" delay="1s"/></transition></state>))
    delayed = handle(stepped, EV.external("e.go", caller_context: context)).effects.grep(E::SendDelayed).first

    assert_same context, delayed.caller_context
    refute_predicate context, :frozen?
  end

  # sabotage: answer `Ractor.make_shareable(seeded)` in place of
  # `Ractor.make_shareable(seeded, copy: true)` in MachineState.seeded; the
  # refute fails, as the host's own array is frozen in place.
  def test_the_state_is_an_immutable_value_and_nothing_the_host_passed_is_frozen
    host = { "h" => [1, 2] }
    started = L.initialize(machine(%(<state id="a"/>)), session_id: "sid", datamodel: host)

    assert Ractor.shareable?(started.state.datamodel)
    assert_predicate started.state, :frozen?
    refute_predicate host["h"], :frozen?
  end

  # sabotage: drop the `raise ArgumentError` line in MachineState.fresh; the
  # assert_raises fails, as the option is ignored.
  def test_starting_refuses_an_option_it_does_not_take
    assert_raises(ArgumentError) { L.initialize(machine(%(<state id="a"/>)), session_id: "sid", tracing: true) }
  end
end
