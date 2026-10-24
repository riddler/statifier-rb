# frozen_string_literal: true

require "test_helper"
require_relative "content_helper"

# The target vocabulary and the send types, as the reference reads them.
class TargetsTest < Minitest::Test
  include ContentHelper

  T = Statifier::Interpreter::Targets

  # sabotage: map "#_parent" to :internal in Targets.parse_target; the
  # assert_equal on the kinds fails.
  def test_targets_parse_to_the_reference_s_routes
    targets = [nil, "#_internal", "_internal", "#_parent", "_parent", "#_scxml_s1", "#_scxml_", "#_i1", "#_", "x", 5]
    parsed = targets.map { T.parse_target(_1).to_h.values }

    assert_equal [[:self, nil], [:internal, nil], [:internal, nil], [:parent, nil], [:parent, nil], [:session, "s1"],
                  [:invoke, "scxml_"], [:invoke, "i1"], [:invalid, "#_"], [:invalid, "x"], [:invalid, 5]], parsed
  end

  # sabotage: answer false for "scxml" in Targets.built_in_type?; the
  # assert_equal on the classes fails.
  def test_types_classify_as_built_in_registered_or_unsupported
    types = [nil, "scxml", "http://www.w3.org/TR/scxml/#SCXMLEventProcessor", "http://www.w3.org/TR/scxml/", "x", 1]

    assert_equal(%i[built_in built_in built_in unsupported registered unsupported],
                 types.map { T.classify(["x"], _1) })
  end

  # sabotage: answer true for :parent in Targets::Routes#reachable?; the
  # assert_equal on the answers fails.
  def test_declared_routes_reach_the_session_its_internal_queue_and_what_they_name
    routes = T::Routes.new(sessions: ["s1"], parent?: false, invokes: ["i1"])
    targets = [nil, "#_internal", "#_scxml_s1", "#_scxml_s2", "#_parent", "#_i1", "#_i2", "x"]

    assert_equal([true, true, true, false, false, true, false, false],
                 targets.map { routes.reachable?(T.parse_target(_1)) })
  end
end
