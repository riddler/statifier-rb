# frozen_string_literal: true

require "test_helper"
require_relative "runner"

# A step's expect_position (Conformance::PositionExpectation in
# test/conformance/position_expectation.rb): the exported position rendered
# as the reference renders it, compared once the step's configuration
# agrees, and the cases the drive refuses before it starts.
class PositionExpectationTest < Minitest::Test
  ROOT = %(xmlns="http://www.w3.org/2005/07/scxml" version="1.0" datamodel="predicator")

  # A chart that records history on leaving a, takes the event's data into
  # v on e.set, and holds a nested value in m.
  HISTORIED = <<~XML
    <datamodel><data id="v" expr="0"/><data id="m" expr="{'z': [1, null], 'a': 'x'}"/></datamodel>
    <state id="a" initial="a2">
      <history id="h"><transition target="a2"/></history>
      <state id="a2"/><state id="a1"/>
      <transition event="e.go" target="b"/>
    </state>
    <state id="b"><transition event="e.set" target="b"><assign location="v" expr="_event.data"/></transition></state>
  XML

  def compiled(body, attributes = "") = Statifier.compile(%(<scxml #{ROOT}#{attributes}>#{body}</scxml>)).value

  def moved(result) = result.value.state

  def started(body, attributes = "") = moved(Statifier.start(compiled(body, attributes), session_id: "s1"))

  def render(state) = Conformance::PositionExpectation.render(state)

  # sabotage: render `_sessionid` (drop it from LEFT_OUT_VARIABLES); the
  # assert_equal on the rendering fails.
  # sabotage: render each history list as `[]` in
  # PositionExpectation.members; the same assert_equal fails.
  def test_the_rendering_has_exactly_the_seven_members_with_every_id_set_sorted
    state = moved(Statifier.step(started(HISTORIED), "e.go"))
    rendering, reason = render(state)

    assert_nil reason
    assert_equal({ "configuration" => %w[b], "entered_states" => %w[a a2 b], "states_to_invoke" => [],
                   "history_values" => { "h" => %w[a2] }, "active_invocations" => [], "running" => true,
                   "datamodel" => { "m" => { "a" => "x", "z" => [1, nil] }, "v" => 0 } }, rendering)
  end

  # A chart whose two parallel regions each hold an invocation, b's
  # written first, and b holding two.
  INVOKING = <<~XML.freeze
    <parallel id="p">
      <state id="b">
        <invoke id="k3"><content><scxml #{ROOT}><state id="x"/></scxml></content></invoke>
        <invoke id="k1"><content><scxml #{ROOT}><state id="x"/></scxml></content></invoke>
      </state>
      <state id="a"><invoke id="k2"><content><scxml #{ROOT}><state id="x"/></scxml></content></invoke></state>
    </parallel>
  XML

  # sabotage: render the invoke id as the index in
  # PositionExpectation.invocations (`"index" => _1["invoke_id"]`); the
  # assert_equal fails.
  def test_each_active_invocation_is_its_state_and_index_sorted_without_its_id
    rendering, = render(started(INVOKING))

    assert_equal [{ "state" => "a", "index" => 0 }, { "state" => "b", "index" => 0 }, { "state" => "b", "index" => 1 }],
                 rendering["active_invocations"]
  end

  # sabotage: always leave `_name` out (drop the `document_name.is_a?`
  # branch in PositionExpectation.datamodel); the second assert_equal fails.
  # sabotage: never leave `_name` out; the first assert_equal fails.
  def test_name_is_rendered_only_when_the_scxml_element_carries_a_name_attribute
    unnamed, = render(started(%(<state id="a"/>)))
    named, = render(started(%(<state id="a"/>), %( name="chart.one")))

    assert_equal({}, unnamed["datamodel"])
    assert_equal({ "_name" => "chart.one" }, named["datamodel"])
  end

  # The state HISTORIED leaves with `value` in v.
  def holding(value) = moved(Statifier.step(moved(Statifier.step(started(HISTORIED), "e.go")), "e.set", data: value))

  NO_FORM = { "date" => Predicator::Date.new(year: 2026, month: 1, day: 2),
              "datetime" => Predicator::DateTime.new(epoch_seconds: 0, microsecond: 0),
              "duration" => Predicator::Duration.new(years: 0, months: 0, weeks: 0, days: 0, hours: 1, minutes: 0,
                                                     seconds: 0, milliseconds: 0) }.freeze

  # sabotage: answer a date as its tagged map in PositionExpectation.json_form
  # (`when Predicator::Date then value.to_h`); the first assert_equal fails.
  def test_a_date_datetime_or_duration_value_fails_naming_the_variable
    NO_FORM.each do |kind, value|
      reason = "the datamodel's v holds a #{kind} value, which has no JSON form here"

      assert_equal [nil, reason], render(holding(value)), kind
    end

    assert_equal "the datamodel's v holds a list value, which has no JSON form here",
                 render(holding([NO_FORM["date"]]))[1]
  end

  # sabotage: answer nil from PositionExpectation.compare whatever differs
  # (`return if true`); the assert_equal on the reason fails.
  def test_a_differing_member_is_named_with_both_values
    state = started(%(<state id="a"/>))
    expected = { "configuration" => %w[b], "entered_states" => %w[a], "states_to_invoke" => [],
                 "history_values" => {}, "active_invocations" => [], "running" => true, "datamodel" => {} }

    assert_equal 'after step 2 (e.go), expect_position differs: configuration: expected ["b"], but got ["a"]',
                 Conformance::PositionExpectation.compare(expected, state, 2, "e.go")
    assert_nil Conformance::PositionExpectation.compare(expected.merge("configuration" => %w[a]), state, 2, "e.go")
    assert_match(/states_to_invoke: expected nothing, but got \[\]/,
                 Conformance::PositionExpectation.compare(expected.except("states_to_invoke"), state, 1, "e"))
  end
end

# The drive's side of a step's expect_position (Conformance::Drive in
# test/conformance/runner.rb): the step's data sent, the position compared,
# a document with an unnamed state refused before the drive, and the diff
# pair accepted and compared by nothing.
class PositionExpectationDriveTest < Minitest::Test
  ROOT = PositionExpectationTest::ROOT

  # A statifier case around body, its one step event e.go with `data`, the
  # step stating `position`.
  def position_case(body, position, data: nil)
    event = { "name" => "e.go" }
    event["data"] = data unless data.nil?
    { "id" => "statifier/x/y", "source" => %(<scxml #{ROOT}>#{body}</scxml>), "initial_configuration" => %w[a],
      "steps" => [{ "event" => event, "configuration" => %w[b], "expect_position" => position }] }
  end

  CARRY = <<~XML
    <datamodel><data id="v" expr="0"/></datamodel>
    <state id="a"><transition event="e.go" target="b"><assign location="v" expr="_event.data"/></transition></state>
    <state id="b"/>
  XML

  def carried(value)
    { "configuration" => %w[b], "entered_states" => %w[a b], "states_to_invoke" => [], "history_values" => {},
      "active_invocations" => [], "running" => true, "datamodel" => { "v" => value } }
  end

  # sabotage: send the name alone for a case with no host object (`data =
  # item.key?("host")` in Drive.drive); the first assert_equal fails.
  # sabotage: drop the position comparison from Drive.drive_step (`[state,
  # failed]`); the second assert_equal fails.
  def test_a_case_with_no_host_stating_a_position_sends_the_step_data_and_compares_the_position
    assert_equal :pass, Conformance::Drive.call(position_case(CARRY, carried(7), data: 7))
    assert_equal "after step 1 (e.go), expect_position differs: datamodel: expected {\"v\":8}, but got {\"v\":7}",
                 Conformance::Drive.call(position_case(CARRY, carried(8), data: 7))
  end

  # sabotage: answer nil from PositionExpectation.named; the assert_equal
  # on the reason fails (the case is then driven).
  def test_a_case_stating_a_position_on_a_document_with_an_unnamed_state_fails_before_it_is_driven
    body = %(<state id="a"><transition event="e.go" target="b"/></state><state id="b"><state/></state>)

    assert_equal "a case that expects a position needs every state to carry an id, " \
                 "and 1 state(s) of this document have none",
                 Conformance::Drive.call(position_case(body, carried(0)))
  end

  # sabotage: drop `to_source` from UNCOMPARED_HOST_KEYS; the assert_equal
  # fails (the case is then refused naming the key).
  def test_a_case_carrying_a_diff_pair_is_driven_and_the_pair_is_compared_by_nothing
    item = position_case(CARRY, carried(0)).except("steps").merge(
      "steps" => [{ "event" => { "name" => "e.go" }, "configuration" => %w[b] }],
      "host" => { "send_types" => [], "expect_sends" => [], "to_source" => "not a document",
                  "expect_diff" => { "anything" => true }, "mapping" => { "x" => "y" },
                  "expect_compatible_at" => ["nowhere"] }
    )

    assert_equal :pass, Conformance::Drive.call(item)
  end
end
