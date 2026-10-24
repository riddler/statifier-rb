# frozen_string_literal: true

require "test_helper"
require_relative "driver_helper"

# Where the driver routes each built-in send: onto the external queue, onto
# the internal queue through the interpreter's internal delivery, or nowhere,
# with error.communication.
class RoutingTest < Minitest::Test
  include DriverHelper

  # sabotage: route `:self` to `:nowhere` in Routing.destination; the
  # assert_equal on the configuration fails.
  def test_a_send_with_no_target_joins_the_external_queue_behind_the_internal_events
    started = start(<<~XML)
      <state id="a">
        <onentry><send event="ext"/><raise event="int"/></onentry>
        <transition event="int" target="b"/><transition event="ext" target="fail"/>
      </state>
      <state id="b"><transition event="ext" target="pass"/></state>
      <state id="pass"/><state id="fail"/>
    XML

    assert_equal %w[pass], active(started)
  end

  # sabotage: compare the session id with `route.id != ...` in
  # Routing.destination; the assert_equal on the configuration fails.
  def test_a_send_to_the_session_s_own_address_joins_its_external_queue
    started = start(<<~XML)
      <state id="a">
        <onentry><send event="e" target="#_scxml_s1"/></onentry>
        <transition event="e" target="b"/><transition event="error.*" target="fail"/>
      </state>
      <state id="b"/><state id="fail"/>
    XML

    assert_equal %w[b], active(started)
  end

  # sabotage: build the delivered event with `origin: nil` in
  # Routing.delivered_event; the assert_equal on the logged fields fails.
  def test_a_delivered_event_comes_from_the_session_through_the_scxml_processor
    started = start(<<~XML)
      <state id="a">
        <onentry><send event="e" id="mine"/><send event="e"/></onentry>
        <transition event="e"><log label="ev" expr="[_event.type, _event.origin, _event.origintype, _event.sendid]"/></transition>
      </state>
    XML
    processor = "http://www.w3.org/TR/scxml/#SCXMLEventProcessor"

    assert_equal [["ev", ["external", "#_scxml_s1", processor, "mine"]],
                  ["ev", ["external", "#_scxml_s1", processor, Predicator::UNDEFINED]]], logs(started)
  end

  # sabotage: answer `:external` for `:internal` in Routing.destination; the
  # assert_equal on the configuration fails, as the event waits behind the
  # external one.
  def test_a_send_to_internal_is_delivered_through_the_internal_queue_ahead_of_external_events
    started = start(<<~XML)
      <state id="a">
        <onentry><send event="ext"/><send event="int" target="#_internal"/></onentry>
        <transition event="int" target="b"><log label="t" expr="_event.type"/></transition><transition event="ext" target="fail"/>
      </state>
      <state id="b"><transition event="ext" target="pass"/></state>
      <state id="pass"/><state id="fail"/>
    XML

    assert_equal %w[pass], active(started)
    assert_equal [%w[t internal]], logs(started)
  end

  # sabotage: append the deferred effects ahead of the batch (`batch +
  # work.effects`) in Run.perform; the assert_equal on the effect order fails.
  def test_an_internal_delivery_s_effects_follow_the_batch_that_sent_it
    started = start(<<~XML)
      <state id="a">
        <onentry><send event="int" target="#_internal"/><log label="after" expr="1"/></onentry>
        <transition event="int"><log label="taken" expr="2"/></transition>
      </state>
    XML

    assert_equal [["after", 1], ["taken", 2]], logs(started)
    assert_equal [E::DatamodelInit, E::Send, E::Log, E::Log], started.effects.map(&:class)
  end

  # sabotage: declare `parent?: true` in Calls.own_routes; the assert_equal on
  # the configuration fails (the core lets the send through and its block
  # goes on to raise `later`).
  def test_an_immediate_send_to_a_parent_the_session_does_not_have_is_refused_in_its_block
    started = start(<<~XML)
      <state id="a">
        <onentry><send event="e" target="#_parent"/><raise event="later"/></onentry>
        <transition event="later" target="fail"/><transition event="error.communication" target="b"/>
      </state>
      <state id="b"><transition event="later" target="fail"/></state><state id="fail"/>
    XML

    assert_equal %w[b], active(started)
  end

  # sabotage: answer `:internal` for every other route in
  # Routing.destination; the assert_equal on the logged sendids fails.
  def test_a_delayed_send_that_reaches_nothing_fails_when_its_timer_fires
    started = start(<<~XML)
      <state id="a">
        <onentry><send event="e" target="#_parent" delay="5ms" id="mine"/><send event="e" target="#_other" delay="5ms"/></onentry>
        <transition event="error.communication"><log label="sendid" expr="_event.sendid"/></transition>
      </state>
    XML

    assert_empty logs(started)
    assert_equal [%w[sendid mine], ["sendid", Predicator::UNDEFINED]], logs(advance(started, 5))
  end

  # sabotage: answer `[work, []]` for a fired send in Routing.internal (drop
  # `return deliver.call(work) unless undelayed`); the assert_equal fails.
  def test_a_fired_send_to_internal_is_delivered_onto_the_internal_queue
    started = start(<<~XML)
      <state id="a">
        <onentry><send event="int" targetexpr="'#_internal'" delay="2ms"/></onentry>
        <transition event="int" target="b"><log label="t" expr="_event.type"/></transition>
      </state>
      <state id="b"/>
    XML
    fired = advance(started, 2)

    assert_equal [%w[b], [%w[t internal]]], [active(fired), logs(fired)]
  end

  # sabotage: answer `[work, []]` for Effect::Done in Run.perform_one; the
  # assert_predicate on the stop fails.
  def test_a_send_a_stopping_chart_makes_to_its_internal_queue_is_never_taken
    stopped = start(%(<final id="f"><onentry><send event="late" target="#_internal"/></onentry></final>))

    assert_predicate Statifier.done?(stopped.state).value, :done?
    assert_equal [E::DatamodelInit, E::Send, E::Done], stopped.effects.map(&:class)
  end

  # sabotage: answer "x" for a send whose event is not text in
  # Routing.name; the assert_equal on the logged name fails.
  def test_a_send_whose_event_is_not_text_delivers_an_event_with_the_empty_name
    started = start(%(<state id="a"><onentry><send eventexpr="5"/></onentry>) +
                    %(<transition event="*"><log label="n" expr="_event.name"/></transition></state>))

    assert_equal [["n", ""]], logs(started)
  end
end
