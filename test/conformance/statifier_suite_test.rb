# frozen_string_literal: true

require "test_helper"
require_relative "runner"

# The statifier suite, the reference's own cases, as the drive answers it:
# every case of its accepts, library, send and system_variables groups
# passes but the ones that ask for what the runner does not do yet, and
# each of those, and every case of the other groups, fails with that
# named.
class StatifierSuiteTest < Minitest::Test
  CORPUS = Conformance::Corpus.load
  CASES = CORPUS.cases_of("statifier")
  RESULTS = CASES.to_h { |item| [item["id"], Conformance::Drive.call(item)] }

  POSITION = "a step states an exported position, which this runner does not compare yet"

  def group(item) = item["id"].split("/")[1]
  def position?(item) = item["steps"].any? { _1.key?("expect_position") }

  # sabotage: compare the handed sends in reverse in Host#verdict; the
  # assert_equal on the passing ids fails (a case handed two sends or more
  # then disagrees).
  # sabotage: drop the exported-position refusal from Drive.unhonoured; the
  # same assert_equal fails (the position cases are then driven and pass,
  # their positions uncompared).
  # sabotage: answer the accepts check with its two lists swapped in
  # Accepts.compare; the same assert_equal fails (the accepts case then
  # disagrees).
  def test_every_accepts_library_send_and_system_variables_case_passes_but_what_the_runner_does_not_do_yet
    groups = CASES.select { %w[accepts library send system_variables].include?(group(_1)) }
    passing = groups.reject { position?(_1) }.map { _1["id"] }

    assert_equal passing, RESULTS.select { _2 == :pass }.keys
    refute_empty passing
  end

  # sabotage: reword the reason Drive.position answers; the assert_equal on
  # the reason of a case stating an exported position fails.
  def test_each_case_left_fails_naming_what_it_asks_for
    CASES.reject { RESULTS[_1["id"]] == :pass }.each do |item|
      assert_equal expected_reason(item), RESULTS[item["id"]], item["id"]
    end
  end

  def expected_reason(item)
    other = item.fetch("host", {}).keys - Conformance::Drive::HONOURED_HOST_KEYS
    return "the case's host object (#{other.join(", ")}) is not honoured here" unless other.empty?

    POSITION
  end
end
