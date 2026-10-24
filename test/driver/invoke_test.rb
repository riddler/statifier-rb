# frozen_string_literal: true

require "test_helper"
require_relative "invoke_helper"

# The driver's invocations: an in-process child session per SCXML
# invocation, what passes between it and its parent, and its cancel.
class DriverInvokeTest < Minitest::Test
  include DriverInvokeHelper

  DONEDATA = %(<final id="f"><donedata><param name="x" expr="42"/></donedata></final>)
  DONE_LOG = %(<log label="done" expr="[_event.data, _event.invokeid, _event.origin, _event.type]"/>)
  UP = %(<state id="x"><onentry><send target="#_parent" event="up"><param name="v" expr="1"/></send></onentry></state>)
  ROUND_TRIP = <<~XML
    <state id="x"><onentry><send target="#_parent" event="up"/></onentry><transition event="down" target="y"/></state>
    <state id="y"><onentry><send target="#_parent" event="got"/></onentry></state>
  XML
  DOWN = <<~XML
    <transition event="up"><send target="#_c" event="down"/><send target="#_nobody" event="lost"/></transition>
    <transition event="error.communication"><log label="err" expr="_event.name"/></transition>
    <transition event="got" target="b"/>
  XML
  FORWARDED = <<~XML
    <state id="x"><transition event="e.go" target="y"/></state>
    <state id="y"><onentry><send target="#_parent" event="moved"/></onentry></state>
  XML
  COMPLETING = <<~XML
    <state id="x"><transition target="f"/></state>
    <final id="f"><onexit><send target="#_parent" event="bye"/></onexit></final>
  XML

  # sabotage: name the child `invoke_id` alone in Invocations.child_start;
  # the assert_equal on the session ids fails.
  def test_the_child_s_session_id_is_its_parent_s_a_dot_and_the_invoke_id
    started = start(invoking(%(<state id="x"><onentry><log label="sid" expr="_sessionid"/></onentry></state>)))

    assert_equal %w[s1.c], started.effects.grep(E::Child).map(&:session_id).uniq
    assert_equal [%w[sid s1.c]], child_logs(started, "s1.c")
    assert_equal %w[c], started.state.invocations.keys
  end

  # sabotage: answer `payload: nil` in place of the donedata in
  # Mailbox.return_done; the assert_equal on the logged event fails.
  def test_a_child_that_finishes_returns_done_invoke_with_its_donedata
    started = start(invoking(DONEDATA, %(<transition event="done.invoke.c" target="b">#{DONE_LOG}</transition>),
                             %(<state id="b"/>)))

    assert_equal [["done", [{ "x" => 42 }, "c", "#_scxml_s1", "external"]]], logs(started)
    assert_equal %w[b], active(started)
    assert_empty started.state.invocations
  end

  # sabotage: drop `.with(invokeid: ...)` in Mailbox.to_parent; the
  # assert_equal on the logged event fails.
  def test_a_send_to_parent_reaches_the_parent_stamped_with_the_invoke_id
    log = %(<log label="up" expr="[_event.data, _event.invokeid, _event.origin]"/>)
    started = start(invoking(UP, %(<transition event="up" target="b">#{log}</transition>), %(<state id="b"/>)))

    assert_equal [["up", [{ "v" => 1 }, "c", "#_scxml_s1.c"]]], logs(started)
  end

  # sabotage: answer `false` for an invocation in Work#reaches?; the
  # assert_equal on the configuration fails.
  def test_a_send_to_the_invoke_id_reaches_the_live_child_and_one_to_no_invocation_fails
    started = start(invoking(ROUND_TRIP, DOWN, %(<state id="b"/>)))

    assert_equal %w[b], active(started)
    assert_equal [%w[err error.communication]], logs(started)
  end

  # sabotage: answer `[work, []]` for an Autoforward in
  # Invocations.perform; the assert_equal on the configuration fails.
  def test_an_autoforwarding_invocation_hands_the_child_the_host_s_event
    started = start(invoking(FORWARDED, %(<transition event="moved" target="b"/>), %(<state id="b"/>),
                             attributes: %(id="c" autoforward="true")))

    assert_equal %w[b], active(step(started, "e.go"))
  end

  # sabotage: answer `work` at once in Invocations.cancel (drop the stop);
  # the assert_equal on the child's logs fails.
  def test_leaving_the_invoking_state_cancels_the_child_which_runs_its_onexit_and_answers_nothing
    child = %(<state id="x"><onexit><log label="bye"/></onexit></state>)
    more = %(<state id="b"><transition event="done.invoke.c" target="fail"/></state><state id="fail"/>)
    left = step(start(invoking(child, %(<transition event="e.leave" target="b"/>), more)), "e.leave")

    assert_equal [["bye", nil]], child_logs(left, "s1.c")
    assert_equal 1, child_effects(left, "s1.c").grep(E::Done).size
    assert_equal [%w[b], {}], [active(left), left.state.invocations]
  end

  # sabotage: answer `work` always in Mailbox.announce; the assert_equal on
  # the configuration fails (the cancel drops the done event).
  def test_a_child_that_said_it_completed_keeps_its_done_event_when_the_parent_leaves_first
    more = %(<state id="b"><transition event="done.invoke.c" target="pass"/></state><state id="pass"/>)
    started = start(invoking(COMPLETING, %(<transition event="bye" target="b"/>), more))

    assert_equal %w[pass], active(started)
  end
end
