# frozen_string_literal: true

require "json"
require "test_helper"
require_relative "../driver/driver_helper"

# A chart driven to a position, and the calls the position tests make.
module PositionHelper
  include DriverHelper

  # a1 counts the e.go events it takes into n; e.out leaves a, recording
  # its history; e.back re-enters it through the history; e.end stops.
  CHART = <<~XML
    <datamodel><data id="n" expr="0"/></datamodel>
    <state id="a" initial="a1">
      <history id="h" type="deep"><transition target="a1"/></history>
      <state id="a1">
        <transition event="e.go" target="a2"><assign location="n" expr="n + 1"/></transition>
      </state>
      <state id="a2"><transition event="e.go" target="a1"><assign location="n" expr="n + 1"/></transition></state>
      <transition event="e.out" target="b"/>
    </state>
    <state id="b"><transition event="e.back" target="h"/><transition event="e.end" target="f"/></state>
    <final id="f"/>
  XML

  # The position after `events`, from a fresh start of CHART.
  def after(*events, **)
    events.reduce(start(CHART, **)) { |moved, name| step(moved, name) }.state
  end

  # The position of `state`, which must export.
  def position(state) = moved(Statifier.export_position(state))

  # The position written to JSON text and read back.
  def through_json(position) = JSON.parse(JSON.generate(position))

  # `state`'s position imported into a fresh compile of CHART.
  def imported(state, **) = moved(Statifier.import_position(machine(CHART), through_json(position(state)), **))

  # The refusal a call answered.
  def refusal(result)
    refute_predicate result, :ok?
    [result.error.reason, result.error.detail]
  end
end
