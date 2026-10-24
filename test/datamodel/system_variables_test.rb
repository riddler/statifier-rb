# frozen_string_literal: true

require "test_helper"
require_relative "datamodel_helper"

# Datamodel::SystemVariables: the four variables of the specification's
# section 5.10, as the reference seeds and rewrites them.
class SystemVariablesTest < Minitest::Test
  include DatamodelHelper

  SV = D::SystemVariables
  SCXML = "http://www.w3.org/TR/scxml/#SCXMLEventProcessor"

  # sabotage: key the SCXML entry by "scxml" in SystemVariables.initial; the
  # assert_equal on the variables fails.
  def test_the_four_variables_before_any_event
    expected = { "_sessionid" => "sid", "_name" => "chart", "_event" => U,
                 "_ioprocessors" => { SCXML => { "location" => "#_scxml_sid" } } }

    assert_equal expected, SV.initial(session_id: "sid", name: "chart")
  end

  # sabotage: bind "_name" to name as given in SystemVariables.initial; the
  # assert_same fails (nil).
  def test_a_chart_with_no_name_binds_name_to_undefined
    assert_same U, SV.initial(session_id: "sid", name: nil)["_name"]
  end

  # sabotage: merge the SCXML entry under the registered entries
  # ({SCXML => ...}.merge(entries)) in SystemVariables.initial; the
  # assert_equal on the SCXML key fails.
  def test_registered_entries_never_replace_the_scxml_entry
    entries = { "t.x" => { "location" => "x" }, SCXML => { "location" => "other" } }
    io = SV.initial(session_id: "sid", name: nil, entries:)["_ioprocessors"]

    assert_equal({ "location" => "x" }, io["t.x"])
    assert_equal({ "location" => "#_scxml_sid" }, io[SCXML])
  end

  # sabotage: merge the host over the system variables
  # (initial(...).merge(host)) in SystemVariables.seed; the assert_equal on
  # "_sessionid" fails.
  def test_the_system_variables_win_over_the_hosts_roots
    seeded = SV.seed({ "x" => 1, "_sessionid" => "host" }, session_id: "sid", name: nil)

    assert_equal [1, "sid"], seeded.values_at("x", "_sessionid")
    assert_predicate seeded, :frozen?
  end

  # sabotage: map a nil field to nil in SystemVariables.absent; the
  # assert_equal fails.
  def test_an_events_value_carries_its_fields_and_undefined_for_the_absent
    value = SV.event(name: "e.go", type: :external, data: nil, sendid: "id1")
    expected = { "name" => "e.go", "type" => "external", "sendid" => "id1", "origin" => U,
                 "origintype" => U, "invokeid" => U, "data" => nil }

    assert_equal expected, value
  end

  # sabotage: drop the unknown-field check in SystemVariables.event; the
  # assert_raises fails.
  def test_an_event_field_the_variable_does_not_have_is_refused
    assert_raises(ArgumentError) { SV.event(name: "e", type: :internal, data: nil, sender: "x") }
  end

  # sabotage: write the event under "event" in SystemVariables.put_event; the
  # assert_equal on _event.name fails.
  def test_put_event_rewrites_event_and_nothing_else
    data = SV.put_event(context({ "x" => 1 }).data, SV.event(name: "e.go", type: :internal, data: { "k" => 2 }))
    evaluated = D.evaluate(D.context(data, machine, []), compiled("[_event.name, _event.type, _event.data.k, x]"))

    assert_equal ["e.go", "internal", 2, 1], evaluated.value
  end
end
