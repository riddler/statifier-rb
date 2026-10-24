# frozen_string_literal: true

require "test_helper"
require_relative "runner"

# The host a case's host object asks for (Conformance::Host in
# test/conformance/host.rb), as the drive registers it: under every type the
# case's `send_types` names, from the start of the chart, the sends handed
# to it compared in order, each with its outcome, against the case's
# `expect_sends`.
class HostTest < Minitest::Test
  ROOT = %(xmlns="http://www.w3.org/2005/07/scxml" version="1.0")

  # Two sends of a registered type on entering the initial state: an
  # immediate one its author names, carrying a payload, and a delayed one
  # with no id and no payload.
  SENDS = <<~XML
    <state id="a">
      <onentry>
        <send type="test:sink" target="t1" event="x" id="named"><param name="k" expr="'v'"/></send>
        <send type="test:sink" target="t2" event="y" delay="10ms"/>
      </onentry>
      <transition event="e.go" target="b"/>
    </state>
    <state id="b"/>
  XML

  IMMEDIATE = { "type" => "test:sink", "target" => "t1", "event" => { "name" => "x", "data" => { "k" => "v" } },
                "send_id" => "named" }.freeze
  DELAYED = { "type" => "test:sink", "target" => "t2", "event" => { "name" => "y" }, "delay_ms" => 10 }.freeze

  # A delayed send of a registered type under the id `r`, cancelled when
  # e.go leaves the state.
  CANCELLED = <<~XML
    <state id="a">
      <onentry><send type="test:sink" target="t" event="later" id="r" delay="10ms"/></onentry>
      <transition event="e.go" target="b"><cancel sendid="r"/></transition>
    </state>
    <state id="b"/>
  XML

  LATER = { "type" => "test:sink", "target" => "t", "event" => { "name" => "later" }, "delay_ms" => 10,
            "send_id" => "r" }.freeze

  # A case around body with a host registering test:sink and expecting
  # `expected`, its steps each sending e.go (with `data` when given).
  def host_case(body, expected, steps: [%w[b]], data: nil)
    event = data.nil? ? { "name" => "e.go" } : { "name" => "e.go", "data" => data }
    { "id" => "statifier/x/y", "source" => %(<scxml #{ROOT}>#{body}</scxml>), "initial_configuration" => %w[a],
      "steps" => steps.map { |expected_leaves| { "event" => event, "configuration" => expected_leaves } },
      "host" => { "send_types" => ["test:sink"], "expect_sends" => expected } }
  end

  def drive(...) = Conformance::Drive.call(host_case(...))

  # sabotage: answer :pass from Host#verdict without comparing; the
  # assert_equal on the reordered expectation's reason fails.
  def test_the_sends_handed_are_compared_in_order_with_the_expected_sends
    assert_equal :pass, drive(SENDS, [IMMEDIATE, DELAYED])
    assert_equal "expected the sends handed to the host #{JSON.generate([DELAYED, IMMEDIATE])}, " \
                 "but got #{JSON.generate([IMMEDIATE, DELAYED])}", drive(SENDS, [DELAYED, IMMEDIATE])
  end

  # sabotage: register the host under no type (answer {} from
  # Host#processors); the assert_equal on the passing case fails (the sends
  # are then refused as unregistered and nothing is handed).
  def test_the_host_is_registered_under_every_send_type_from_the_start
    assert_equal :pass, drive(SENDS, [IMMEDIATE, DELAYED], steps: [])
    assert_match(/\Aexpected the sends handed to the host \[\], but got /, drive(SENDS, []))
  end

  # sabotage: write the send id on every item in Host.item (`item["send_id"]
  # = send.send_id`); the assert_equal on the passing case fails (the
  # delayed send's generated id appears).
  def test_an_item_carries_a_send_id_only_when_the_author_named_it_and_a_payload_only_when_there_is_one
    item = Conformance::Drive.call(host_case(SENDS, [])).then { |reason| JSON.parse(reason[/but got (.*)\z/, 1]) }

    assert_equal [IMMEDIATE, DELAYED], item
  end

  # sabotage: mark every cancelled send whatever its expected item says
  # (answer true from Host#cancelled?); the last assert_equal fails (the
  # unmarked expectation then disagrees).
  def test_a_cancel_marks_the_delayed_send_whose_expected_item_asks_for_it
    marked = LATER.merge("outcome" => "cancelled")

    assert_equal :pass, drive(CANCELLED, [marked])
    assert_match(/but got \[\{.*"send_id":"r"\}\]\z/, drive(CANCELLED, [marked], steps: []))
    assert_equal :pass, drive(CANCELLED, [LATER])
  end

  # sabotage: answer nil from Host.unreported; the
  # assert_equal on the reason fails (the case is then driven and its sends
  # disagree).
  def test_an_expected_send_to_report_failed_is_refused_naming_it
    failed = IMMEDIATE.merge("outcome" => "fail")

    assert_equal "an expected send asks the host to report it failed, which this runner does not report yet",
                 drive(SENDS, [failed, DELAYED])
  end

  # sabotage: send UNDEFINED as every step's data in Drive.drive_step; the
  # assert_equal on the passing case fails (the param then reads nothing).
  def test_a_step_of_a_host_case_sends_its_event_data
    send = %(<send type="test:sink" target="t" event="x"><param name="d" expr="_event.data.k"/></send>)
    body = %(<state id="a"><transition event="e.go" target="b">#{send}</transition></state><state id="b"/>)
    expected = [{ "type" => "test:sink", "target" => "t", "event" => { "name" => "x", "data" => { "d" => 1 } } }]

    assert_equal :pass, drive(body, expected, data: { "k" => 1 })
  end
end
