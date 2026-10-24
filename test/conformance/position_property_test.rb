# frozen_string_literal: true

require "test_helper"
require_relative "position_property"

# The position round-trip property (Conformance::PositionProperty): over the
# vendored scion suite every point a position carries continues exactly as
# the unbroken drive does, a point it cannot carry is counted with its
# reason, and a position that loses a field on the way out is caught.
class PositionPropertyTest < Minitest::Test
  P = Conformance::PositionProperty
  ROOT = %(xmlns="http://www.w3.org/2005/07/scxml" version="1.0" datamodel="predicator")

  # a waits 50 ms on its timer for b; b counts e.go into n on the way to c,
  # which stops at f on e.end.
  TIMED = <<~XML
    <datamodel><data id="n" expr="0"/></datamodel>
    <state id="a"><onentry><send event="t" delay="50ms"/></onentry><transition event="t" target="b"/></state>
    <state id="b"><transition event="e.go" target="c"><assign location="n" expr="n + 1"/></transition></state>
    <state id="c"><transition event="e.end" target="f"/></state>
    <final id="f"/>
  XML

  def self.scion = @scion ||= P.scion

  # The property over the scion suite, run once for the class.
  def self.report = @report ||= P.run(scion)

  # A case of the scion suite's shape around body.
  def chart_case(body, initial, steps)
    { "id" => "scion/x/y", "source" => %(<scxml #{ROOT}>#{body}</scxml>), "initial_configuration" => initial,
      "steps" => steps.map { |name, expected| { "event" => { "name" => name }, "configuration" => expected } } }
  end

  # An export that hands the position through `change` before it travels.
  def planted(&change)
    lambda do |state|
      exported = Statifier.export_position(state)
      exported.ok? ? Statifier::Result.new(value: change.call(exported.value), error: nil) : exported
    end
  end

  def timed_case = chart_case(TIMED, %w[b], [["e.go", %w[c]], ["e.end", %w[f]]])

  # The counts move only with the corpus or with what the driver leaves
  # pending at a point; a change in either is read here before it lands.
  # sabotage: export the recorded history as empty in Position.exported
  # (`"history_values" => {}`); the assert_equal on the disagreements fails.
  def test_every_point_after_every_start_and_step_of_the_scion_suite_that_is_carried_agrees
    report = self.class.report

    assert_equal [], report.disagreements
    assert_equal [119, 199, 318, 313, { pending_timers: 5 }],
                 [report.cases, report.steps, report.points, report.agreeing, report.not_carried]
    assert_equal [], P.stage_failures(report)
  end

  def test_the_report_prints_its_points_agreements_and_reasons
    assert_equal ["position: 318 points over 119 scion cases (119 starts and 199 steps)",
                  "position: 313 round trips agree, 0 disagree",
                  "position: 5 points not carried: pending_timers 5"], P.lines(self.class.report)
  end

  def test_a_position_that_loses_the_recorded_history_disagrees
    report = P.run(self.class.scion, export: planted { _1.merge("history_values" => {}) })

    assert_includes report.disagreements.map(&:first), "scion/history/history0"
  end

  def test_a_position_that_loses_a_required_key_is_refused_at_every_point
    report = P.run(self.class.scion, export: planted { _1.except("history_values") })

    assert_equal 0, report.agreeing
    assert_equal "the import was refused: malformed_export", report.disagreements.first.last
  end

  def test_a_position_that_loses_a_field_no_configuration_shows_disagrees_at_the_import
    report = P.run(self.class.scion, export: planted { _1.merge("entered_states" => []) })

    assert_equal 0, report.agreeing
    assert_match(/\Aat the import: entered_states /, report.disagreements.first.last)
  end

  # sabotage: drop the pending-timer line in PositionProperty.driver_held;
  # the assert_equal on the outcomes fails (the start disagrees).
  def test_a_point_with_a_pending_timer_is_not_carried_and_the_rest_are_compared
    body = <<~XML
      <state id="a"><onentry><send id="k" event="t" delay="5s"/></onentry>
        <transition event="e.go" target="b"><cancel sendid="k"/></transition></state>
      <state id="b"><transition event="e.end" target="f"/></state><final id="f"/>
    XML
    item = chart_case(body, %w[a], [["e.go", %w[b]], ["e.end", %w[f]]])
    points = P.round_trips(item, Statifier.method(:export_position))

    assert_equal([[0, :not_carried, :pending_timers], [1, :agree, nil], [2, :agree, nil]],
                 points.map { [_1.point, _1.outcome, _1.reason] })
  end

  # sabotage: compare the datamodel by value rather than by its text in
  # PositionProperty.carried (drop the encode); the assert_equal on the
  # reason fails (1.0 and 1 compare equal).
  def test_a_carried_point_that_disagrees_names_the_point_and_the_field
    points = P.round_trips(timed_case, planted { _1.merge("datamodel" => _1["datamodel"].merge("n" => "0.0")) })

    assert_equal [0, :disagree, %(at the import: datamodel.n is "0.0", the unbroken drive's "0")],
                 [points[0].point, points[0].outcome, points[0].reason]
  end

  # sabotage: compare the configuration a chart stopped in even when it was
  # stopped at the point (drop `stopped_at_point ||` in
  # PositionProperty.done_disagreement); the assert_equal on the outcomes
  # fails.
  def test_a_point_after_the_chart_stopped_agrees_on_having_stopped
    points = P.round_trips(timed_case, Statifier.method(:export_position))

    assert_equal %i[agree agree agree], points.map(&:outcome)
  end

  # sabotage: drop the zero-agreement line in PositionProperty.stage_failures;
  # the assert_equal on the failures fails.
  def test_a_run_where_no_point_agrees_fails_the_stage
    refusal = Statifier::Position::Refusal.new(reason: :internal_queue_not_empty, detail: {})
    refused = Statifier::Result.new(value: nil, error: refusal)
    report = P.run([timed_case], export: ->(_) { refused })

    assert_equal ["position: no round trip agrees over 3 points"], P.stage_failures(report)
  end

  # sabotage: let every reason through PositionProperty.stage_failures
  # (an empty reject); the assert_equal on the failures fails.
  def test_a_point_not_carried_for_an_unexpected_reason_fails_the_stage
    item = chart_case(%(<state id="a"><transition event="e.go" target="u"/></state><state><state id="u"/></state>),
                      %w[a], [["e.go", %w[u]]])
    report = P.run([item])

    assert_equal [{ unnameable_states: 1 }, 1], [report.not_carried, report.agreeing]
    assert_equal ["position: 1 points not carried for unnameable_states"], P.stage_failures(report)
  end
end
