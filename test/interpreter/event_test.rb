# frozen_string_literal: true

require "test_helper"

# The one event value every queue holds, and a failure as the data its
# error event carries.
class EventTest < Minitest::Test
  EV = Statifier::Event
  DM = Internals::Datamodel

  # sabotage: pass `type: :external` in Event.internal; the assert_equal on
  # the types fails.
  def test_each_constructor_answers_its_type_and_leaves_origin_blank_for_raised_events
    cause = EV::Cause.new(origin: { kind: :state, state_index: 1 }, macrostep: 1, microstep: 2, round: 3)
    events = [EV.external("e", origin: "#_scxml_x", origintype: "t"), EV.internal("e", cause, sendid: "s"),
              EV.platform("e", cause, data: 1)]

    assert_equal %i[external internal platform], events.map(&:type)
    assert_equal([["#_scxml_x", nil], [nil, "s"], [nil, nil]], events.map { [_1.origin, _1.sendid] })
    assert_equal [nil, cause, cause], events.map(&:cause)
    assert_same Predicator::UNDEFINED, events.first.data
  end

  # sabotage: slice only :name, :type and :data in SystemVariables.of_event;
  # the assert_equal fails, as SystemVariables.event reads the rest as absent.
  def test_the_system_value_carries_every_field_of_underscore_event
    value = DM::SystemVariables.of_event(EV.external("e", data: [1], invokeid: "i", sendid: "s"))

    assert_equal({ "name" => "e", "type" => "external", "sendid" => "s", "origin" => Predicator::UNDEFINED,
                   "origintype" => Predicator::UNDEFINED, "invokeid" => "i", "data" => [1] }, value)
  end

  # sabotage: answer `reason` for a Data in Datamodel::ReasonValue.of; the
  # assert_equal fails.
  def test_a_failure_becomes_a_predicator_value_with_its_kind_in_snake_case
    inner = DM::UnboundLocation.new(location: :zz)
    reason = Internals::Interpreter::Content::NestedContent.new(c_index: 2, reason: inner)

    assert_equal({ "kind" => "nested_content", "c_index" => 2,
                   "reason" => { "kind" => "unbound_location", "location" => "zz" } }, DM::ReasonValue.of(reason))
  end

  # sabotage: drop the VALUE_TYPES arm in Datamodel::ReasonValue.of; the
  # assert_same fails, as the duration becomes a Hash.
  def test_a_predicator_value_inside_a_failure_stays_as_it_is
    duration = Predicator.parse_duration("1s").value

    assert_same duration, DM::ReasonValue.of(Internals::Interpreter::Foreach::NotIterable.new(value: duration))["value"]
    assert_same duration, DM::ReasonValue.of(DM::InvalidDelay.new(value: duration))["value"]
  end
end
