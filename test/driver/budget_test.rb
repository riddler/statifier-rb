# frozen_string_literal: true

require "test_helper"
require_relative "driver_helper"

# The round budget a call spends: a macrostep's, which halts the driver,
# and the call's own counts of the events undelayed sends queue and the
# internal sends it delivers.
class BudgetTest < Minitest::Test
  include DriverHelper

  SELF_LOOP = %(<state id="a"><onentry><send event="again"/></onentry><transition event="again" target="a"/></state>)
  INTERNAL_LOOP = %(<state id="a"><onentry><send event="again" target="#_internal"/></onentry>) +
                  %(<transition event="again" target="a"/></state>)

  HALTING = <<~XML
    <state id="a">
      <onentry>
        <send event="later" delay="1ms"/><send event="inside" delay="1ms" targetexpr="'#_internal'"/>
        <send event="away" delay="1ms" target="#_parent"/><send event="again"/>
      </onentry>
      <transition event="again" target="a"/>
      <transition event="inside"><log label="i"/></transition><transition event="error.*"><log label="e"/></transition>
    </state>
  XML

  # sabotage: halt one event later (`work.within?(work.taken - 1)` in
  # Run.drain); the assert_equal on the macrostep fails.
  def test_a_call_halts_once_it_takes_more_self_sent_events_than_its_budget
    started = start(SELF_LOOP, max_macrostep_rounds: 3)

    assert_equal :budget_exhausted, started.state.halted
    assert_equal [1, 1, 4], [started.effects.grep(E::BudgetExhausted).size, started.state.external_queue.size,
                             started.state.machine_state.macrostep]
  end

  # sabotage: count one send more (`work.within?(work.sent_internal + 1)`
  # in Routing.internal); the assert_equal on the sends fails.
  def test_a_call_halts_once_it_delivers_more_internal_sends_than_its_budget
    started = start(INTERNAL_LOOP, max_macrostep_rounds: 3)

    assert_equal :budget_exhausted, started.state.halted
    assert_equal([1, 4], [E::BudgetExhausted, E::Send].map { started.effects.grep(_1).size })
    assert_equal %w[again], started.state.machine_state.internal_queue.map(&:name)
  end

  # sabotage: drop the `halted.nil?` check in Run.next_event; the
  # assert_equal on the queued events fails (the event is taken).
  def test_a_halted_chart_queues_further_events_and_takes_none
    started = start(SELF_LOOP, max_macrostep_rounds: 3)
    stepped = step(started, "e.more")

    assert_equal %w[again e.more], stepped.state.external_queue.map(&:name)
    assert_empty stepped.effects
  end

  # sabotage: route a fired send the usual way while halted (drop the
  # `halted.nil?` branch in Calls.fire); the assert_empty on the effects
  # fails (the internal and parent sends are routed and run the chart).
  def test_timers_still_fire_while_halted_and_a_send_to_the_session_waits
    fired = advance(start(HALTING, max_macrostep_rounds: 3), 1)

    assert_empty fired.effects
    assert_equal "later", fired.state.external_queue.last.name
    assert_empty fired.state.timers
  end

  # sabotage: answer `count.zero?` for an `:infinity` budget in
  # Work#within?; the call halts and the assert_nil fails.
  def test_an_infinite_budget_bounds_neither_count
    started = start(<<~XML, max_macrostep_rounds: :infinity)
      <datamodel><data id="n" expr="0"/></datamodel>
      <state id="a">
        <onentry><assign location="n" expr="n + 1"/><if cond="n &lt; 50"><send event="again"/></if></onentry>
        <transition event="again" target="a"/>
      </state>
    XML

    assert_nil started.state.halted
    assert_empty started.state.external_queue
  end
end
