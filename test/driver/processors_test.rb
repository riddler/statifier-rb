# frozen_string_literal: true

require "test_helper"
require_relative "driver_helper"

# Registered send types: each send handed to the host's processor, a
# delayed one held and its cancel told once, the _ioprocessors entries, and
# the processors a call must pass.
class ProcessorsTest < Minitest::Test
  include DriverHelper

  CHART = <<~XML
    <state id="a">
      <onentry>
        <send event="now" type="x-rec" target="route-1" id="n"/>
        <send event="later" type="x-rec" target="route-2" delay="5ms" id="d"/>
      </onentry>
      <transition event="e.cancel"><cancel sendid="d"/><cancel sendid="d"/></transition>
      <transition event="error.*" target="fail"/>
    </state>
    <state id="fail"/>
  XML

  # sabotage: answer false from Routing.registered?; the assert_equal on the
  # handed sends fails (they are routed, and fail).
  def test_a_send_of_a_registered_type_is_handed_to_its_processor_and_never_routed
    recorder = Recorder.new
    started = start(CHART, processors: { "x-rec" => recorder })
    handed = recorder.calls.map { |kind, send, event, context| [kind, send.target, event.name, context.session_id] }

    assert_equal [[:deliver, "route-1", "now", "s1"], [:deliver, "route-2", "later", "s1"]], handed
    assert_equal %w[a], active(started)
    assert_empty started.state.timers
  end

  # sabotage: hand the processor the event with `sendid: nil` (drop
  # `author_id`) in Routing.delivered_event; the assert_equal fails.
  def test_the_processor_is_handed_the_event_a_delivery_would_carry
    recorder = Recorder.new
    start(CHART, processors: { "x-rec" => recorder })
    event = recorder.calls.first[2]

    assert_equal ["now", :external, "#_scxml_s1", "n"], [event.name, event.type, event.origin, event.sendid]
  end

  # sabotage: drop the `release` in Routing.cancel; the assert_equal on the
  # cancels fails (the second cancel reaches the processor too).
  def test_a_cancel_of_a_held_send_reaches_its_processor_once
    recorder = Recorder.new
    processors = { "x-rec" => recorder }
    step(start(CHART, processors:), "e.cancel", processors:)
    cancels = recorder.calls.select { _1.first == :cancel }
                      .map { |_, cancel, context| [cancel.send_id, context.session_id] }

    assert_equal [%w[d s1]], cancels
  end

  # sabotage: answer `{}` for every type in Calls.entries; the assert_equal
  # on the logged entries fails.
  def test_each_registered_type_has_its_ioprocessors_entry
    deliver_only = Object.new
    def deliver_only.deliver(*) = nil
    processors = { "x-rec" => Recorder.new(entry: { "location" => "here" }), "x-bare" => deliver_only }
    started = start(<<~XML, processors:)
      <state id="a"><onentry><log label="io" expr="[_ioprocessors['x-rec'], _ioprocessors['x-bare']]"/></onentry></state>
    XML

    assert_equal [["io", [{ "location" => "here", "session" => "s1" }, {}]]], logs(started)
  end

  # sabotage: answer `state` whatever the processors name in Checks.state;
  # the assert_raises fails.
  def test_every_later_call_passes_processors_for_the_types_the_chart_started_with
    started = start(CHART, processors: { "x-rec" => Recorder.new })

    assert_raises(ArgumentError) { Statifier.step(started.state, "e") }
    assert_raises(ArgumentError) { Statifier.advance(started.state, 1, processors: { "x-other" => Recorder.new }) }
  end

  # sabotage: register the types unsorted (drop `.sort` in
  # Checks.registered_types); the assert_equal on the state's types fails.
  def test_a_type_the_host_did_not_register_is_refused_by_the_core
    started = start(CHART, processors: { "x-z" => Recorder.new, "x-a" => Recorder.new })

    assert_equal %w[x-a x-z], started.state.send_types
    assert_equal %w[fail], active(started)
  end
end
