# frozen_string_literal: true

require "test_helper"
require_relative "runner"

# The drive (Conformance::Drive in test/conformance/runner.rb): each case
# compiled and driven through the driver, its active leaves compared after
# the start and after each step, on the virtual clock's two knobs.
class DriveTest < Minitest::Test
  ROOT = %(xmlns="http://www.w3.org/2005/07/scxml" version="1.0")

  GUARDED = <<~XML
    <state id="a">
      <onentry><send event="t" delay="50ms"/><send event="guard" delay="5s"/></onentry>
      <transition event="t" target="b"/><transition event="guard" target="late"/>
    </state>
    <state id="b"><transition event="e.go" target="c"/><transition event="guard" target="late"/></state>
    <state id="c"/><state id="late"/>
  XML

  # A case of the scion suite's shape around body, with its expectations.
  def chart_case(body, initial, steps = [])
    { "id" => "scion/x/y", "source" => %(<scxml #{ROOT}>#{body}</scxml>), "initial_configuration" => initial,
      "steps" => steps.map { |name, expected| { "event" => { "name" => name }, "configuration" => expected } } }
  end

  def drive(...) = Conformance::Drive.call(chart_case(...))

  # A chart whose one timer, due after `delay`, moves it from a to b.
  def timed(delay)
    "<state id=\"a\"><onentry><send event=\"t\" delay=\"#{delay}\"/></onentry>" \
      "<transition event=\"t\" target=\"b\"/></state><state id=\"b\"/>"
  end

  # sabotage: answer the leaves unsorted (drop `.sort` in Drive.leaves); the
  # assert_equal on the passing case fails.
  def test_the_drive_starts_the_chart_and_compares_the_active_leaves_after_each_step
    body = %(<parallel id="p"><state id="y"/><state id="x"><transition event="e.go" target="z"/></state></parallel>) +
           %(<state id="z"/>)

    assert_equal :pass, drive(body, %w[x y], [["e.go", %w[z]]])
    assert_equal 'step 1 (event "e.go"): expected active leaf states ["q"], got ["z"]',
                 drive(body, %w[x y], [["e.go", %w[q]]])
  end

  # sabotage: answer nil for a case with a host object (drop the `host` line
  # in Drive.unhonoured); the assert_match on the reason fails.
  def test_a_case_asking_what_the_runner_does_not_honour_fails_naming_it
    host = Conformance::Corpus.load.cases.find { |item| item.key?("host") && !item["host"].key?("event_io_processors") }

    assert_match(/\Athe case's host object \(send_types/, Conformance::Drive.call(host))
    assert_match(/does not compile/, drive("<state", []))
  end

  # sabotage: set SETTLE_WINDOW_MS to 5000; the assert_equal on the guarded
  # case fails (the guard fires before the event).
  def test_the_clock_settles_short_timers_before_the_next_event_and_never_a_guard
    assert_equal [100, 4000], [Conformance::Drive::SETTLE_WINDOW_MS, Conformance::Drive::CONFIGURATION_DEADLINE_MS]
    assert_equal :pass, drive(GUARDED, %w[b], [["e.go", %w[c]]])
  end

  # sabotage: set CONFIGURATION_DEADLINE_MS to 1000; the first assert_equal
  # fails (the 3s timer is never waited for).
  def test_the_drive_waits_for_the_expectation_up_to_its_deadline
    assert_equal :pass, drive(timed("3s"), %w[b])
    assert_equal 'the initial configuration: expected active leaf states ["b"], got ["a"]', drive(timed("5s"), %w[b])
  end

  # sabotage: answer `state.machine_state.configuration` in Drive.active;
  # the assert_equal fails (a stopped chart has no active state).
  def test_a_stopped_chart_is_compared_at_the_states_it_stopped_in
    assert_equal :pass, drive(%(<state id="a"><transition target="f"/></state><final id="f"/>), %w[f])
  end

  # sabotage: answer `0` in place of the unnamed count in Drive.leaves;
  # the assert_equal on the reason fails.
  def test_an_active_leaf_with_no_id_fails_the_case
    assert_equal "the initial configuration: 1 active leaf state(s) have no id; the expectation cannot name them",
                 drive(%(<parallel id="p"><state id="x"/><state/></parallel>), %w[x])
  end
end
