# frozen_string_literal: true

require "test_helper"
require_relative "driver_helper"

# The virtual clock: delayed sends as pending timers, advance firing them in
# due-then-scheduled order, cancel removing them, and the stop discarding
# them.
class TimersTest < Minitest::Test
  include DriverHelper

  ORDER = <<~XML
    <state id="a">
      <onentry><send event="late" delay="20ms"/><send event="first" delay="10ms"/><send event="second" delay="10ms"/></onentry>
      <transition event="*"><log label="ev" expr="_event.name"/></transition>
    </state>
  XML

  # sabotage: compare `_1.due_ms < until_ms` in Calls.next_due; the
  # assert_equal on the advance to 10 fails (nothing fires).
  def test_advance_fires_what_is_due_by_the_new_time_and_keeps_the_rest_pending
    started = start(ORDER)

    assert_empty logs(advance(started, 9))
    assert_equal [%w[ev first], %w[ev second]], logs(advance(started, 10))
    assert_equal 1, advance(started, 10).state.timers.size
  end

  # sabotage: order by `[_1.due_ms, -_1.sequence]` in Calls.next_due; the
  # assert_equal on the order fails.
  def test_timers_fire_earliest_first_and_in_the_order_scheduled_at_one_due_time
    assert_equal [%w[ev first], %w[ev second], %w[ev late]], logs(advance(start(ORDER), 25))
  end

  # sabotage: leave `now_ms` at the timer's due time (drop the final
  # `with_state(now_ms: until_ms)` in Calls.advance); the assert_equal on the
  # clock fails.
  def test_the_clock_ends_where_it_was_moved_to_and_counts_on_from_there
    advanced = advance(advance(start(ORDER), 4), 6)

    assert_equal 10, advanced.state.now_ms
    assert_equal [%w[ev first], %w[ev second]], logs(advanced)
  end

  # sabotage: reject timers by `_1.send_id != id` in Routing.cancel; the
  # assert_equal on what fires fails.
  def test_a_cancel_removes_every_pending_timer_under_its_send_id
    started = start(<<~XML)
      <state id="a">
        <onentry><send event="gone" delay="10ms" id="t"/><send event="kept" delay="10ms" id="k"/></onentry>
        <transition event="e.stop"><cancel sendid="t"/></transition>
        <transition event="*"><log label="ev" expr="_event.name"/></transition>
      </state>
    XML

    assert_equal [%w[ev kept]], logs(advance(step(started, "e.stop"), 10))
  end

  # sabotage: drop `timers: [].freeze` in Run.stopped; the assert_empty on
  # the stopped chart's timers fails.
  def test_the_stop_discards_pending_timers_and_queued_events
    stopped = start(%(<state id="a"><onentry><send event="later" delay="10ms"/><send event="e"/></onentry>) +
                    %(<transition target="f"/></state><final id="f"/>))

    assert_predicate Statifier.done?(stopped.state).value, :done?
    assert_empty stopped.state.timers
    assert_empty stopped.state.external_queue
  end

  # sabotage: drop the `value >= 0` check in Calls.duration?; the
  # assert_equal on the negative duration fails.
  def test_advance_refuses_a_duration_the_clock_cannot_move_by
    state = start(ORDER).state

    errors = [-1, Float::INFINITY, Float::NAN, "1"].map { Statifier.advance(state, _1).error }

    assert_equal [:invalid_duration] * 4, errors
  end

  # sabotage: build the delivered event with `data: Predicator::UNDEFINED`
  # in Routing.delivered_event; the assert_equal on the logged fields fails.
  def test_a_fired_send_s_event_carries_the_delayed_send_s_fields
    fired = advance(start(<<~XML), 1)
      <state id="a">
        <onentry><send event="e" delay="1ms" id="d"><param name="p" expr="3"/></send></onentry>
        <transition event="e"><log label="ev" expr="[_event.data, _event.sendid]"/></transition>
      </state>
    XML

    assert_equal [["ev", [{ "p" => 3 }, "d"]]], logs(fired)
  end
end
