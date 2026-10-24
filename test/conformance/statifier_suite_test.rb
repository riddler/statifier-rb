# frozen_string_literal: true

require "test_helper"
require_relative "runner"

# The statifier suite, the reference's own cases, as the drive answers it:
# every case of every group passes, the diff cases driven with their diff
# pair compared by nothing and the cases stating an exported position
# compared on it.
class StatifierSuiteTest < Minitest::Test
  CORPUS = Conformance::Corpus.load
  CASES = CORPUS.cases_of("statifier")
  RESULTS = CASES.to_h { |item| [item["id"], Conformance::Drive.call(item)] }

  # sabotage: compare the handed sends in reverse in Host#verdict; the
  # assert_equal fails (a case handed two sends or more then disagrees).
  # sabotage: answer the accepts check with its two lists swapped in
  # Accepts.compare; the assert_equal fails (the accepts case then
  # disagrees).
  # sabotage: render `_name` whatever the document (drop it from the
  # left-out list in PositionExpectation.datamodel); the assert_equal fails
  # (the four cases stating a position then disagree on their datamodel).
  def test_every_case_of_the_suite_passes
    assert_equal CASES.to_h { [_1["id"], :pass] }, RESULTS
    assert_equal 36, CASES.size
  end

  # The first case stating a position.
  POSITIONED = CASES.find { _1["steps"].any? { |step| step.key?("expect_position") } }

  # That case, its first such step's `running` flipped: `[case, step
  # number, the flag the case states now]`.
  def flipped
    altered = Marshal.load(Marshal.dump(POSITIONED))
    index = altered["steps"].index { _1.key?("expect_position") }
    position = altered["steps"][index]["expect_position"]
    position["running"] = !position["running"]
    [altered, index + 1, position["running"]]
  end

  # sabotage: answer nil from PositionExpectation.compare (`return if
  # true`); the assert_match on the reason fails.
  def test_a_case_stating_a_position_the_chart_does_not_hold_fails_naming_the_member
    altered, number, running = flipped
    differs = "expect_position differs: running: expected #{running}, but got #{!running}"

    assert_match(/\Aafter step #{number} \(.*\), #{differs}\z/, Conformance::Drive.call(altered))
  end
end
