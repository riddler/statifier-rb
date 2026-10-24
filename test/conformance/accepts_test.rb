# frozen_string_literal: true

require "test_helper"
require_relative "runner"

# The accepts check a case's host object asks for (Conformance::Accepts in
# test/conformance/accepts.rb), compared before the chart is driven.
class AcceptsDriveTest < Minitest::Test
  ROOT = %(xmlns="http://www.w3.org/2005/07/scxml" version="1.0")

  # A case whose host object is `host`, around a chart listening for
  # `e.go` in a and `e.back` in b.
  def accepts_case(host)
    body = %(<state id="a"><transition event="e.go" target="b"/></state>) +
           %(<state id="b"><transition event="e.back" target="a"/></state>)
    { "id" => "statifier/x/y", "source" => %(<scxml #{ROOT}>#{body}</scxml>), "initial_configuration" => %w[a],
      "steps" => [{ "event" => { "name" => "e.go" }, "configuration" => %w[b] }], "host" => host }
  end

  # sabotage: compare the two lists sorted in Accepts.compare; the second
  # assert_equal fails (the case with the lists out of order then passes).
  def test_the_accepts_check_is_compared_exactly_order_included
    expected = { "unreachable" => %w[e.y e.x], "undeclared" => %w[e.go e.back] }
    item = accepts_case("declared_events" => %w[e.y e.x], "expect_accepts" => expected)

    assert_equal :pass, Conformance::Drive.call(item)
    item["host"]["expect_accepts"] = { "unreachable" => %w[e.x e.y], "undeclared" => %w[e.back e.go] }

    assert_equal 'expected the accepts check {"unreachable":["e.x","e.y"],"undeclared":["e.back","e.go"]}, ' \
                 'but got {"unreachable":["e.y","e.x"],"undeclared":["e.go","e.back"]}', Conformance::Drive.call(item)
  end

  # sabotage: compare the accepts check after the drive in Drive.call; the
  # assert_equal fails (the wrong configuration is reported first).
  def test_an_accepts_disagreement_is_reported_before_the_chart_is_driven
    item = accepts_case("declared_events" => [], "expect_accepts" => { "unreachable" => [], "undeclared" => [] })
    item["initial_configuration"] = %w[b]

    assert_match(/\Aexpected the accepts check /, Conformance::Drive.call(item))
  end

  # sabotage: drop the `unless expected` line in Accepts.disagreement; the first
  # assert_equal fails (the check is then compared with nothing).
  def test_either_accepts_key_without_the_other_fails_the_case_naming_it
    assert_equal "declared_events is present without expect_accepts",
                 Conformance::Drive.call(accepts_case("declared_events" => %w[e.go e.back]))
    assert_equal "expect_accepts is present without declared_events",
                 Conformance::Drive.call(accepts_case("expect_accepts" => { "unreachable" => [], "undeclared" => [] }))
  end
end
