# frozen_string_literal: true

require "test_helper"
require_relative "datamodel_helper"

# Datamodel::Location.write: an <assign>'s write, in the reference's order of
# checks, with the path it resolved to and the value the path held.
class LocationTest < Minitest::Test
  include DatamodelHelper

  HOST = { "x" => nil, "l" => [10, 20], "m" => { "k" => 1 }, "k" => "k", "i" => 2, "s" => "str" }.freeze

  # Each location written with 7, with the reference's answer at its tag
  # (Statifier.Interpreter.Datamodel.write_location/4 against the same
  # datamodel): the path, the value it held and the root written.
  WRITES = [
    ["x", ["x"], nil, ["x", 7]],
    ["x.a.b", %w[x a b], U, ["x", { "a" => { "b" => 7 } }]],
    ["l[1]", ["l", 1], 20, ["l", [10, 7]]],
    ["l[5]", ["l", 5], U, ["l", [10, 20, U, U, U, 7]]],
    ["m.k", %w[m k], 1, ["m", { "k" => 7 }]],
    ["m[k]", %w[m k], 1, ["m", { "k" => 7 }]],
    ["m[i]", ["m", 2], U, ["m", { "k" => 1, 2 => 7 }]],
    ["x[0]", ["x", 0], U, ["x", [7]]]
  ].freeze

  # sabotage: evaluate the bracket keys against an empty Hash in
  # Location.write; the assert_predicate on ok? fails for m[k].
  def test_a_write_answers_its_path_its_prior_value_and_the_bound_root
    WRITES.each do |location, path, prior, (root, value)|
      written = D::Location.write(context(HOST), location, 7)

      assert_predicate written, :ok?, location
      assert_equal [path, prior, value], [written.path, written.prior_value, written.context.data[root]], location
    end
  end

  # sabotage: swap the two root checks in Location.checked; the assert_equal
  # fails, as the undeclared _x reports an unbound location.
  def test_a_system_root_is_refused_before_the_root_check
    refusals = %w[_event _event.name _x].map { D::Location.write(context(HOST), _1, 7).error }

    assert_equal %w[_event _event _x].map { D::SystemVariable.new(root: _1) }, refusals
  end

  # sabotage: drop the key? check in Location.checked; the assert_equal
  # fails, as the write declares the root.
  def test_a_root_the_datamodel_does_not_hold_is_refused
    assert_equal [D::UnboundLocation.new(location: "nope.a")], [D::Location.write(context(HOST), "nope.a", 7).error]
  end

  # sabotage: refuse as UnboundLocation.new(location:) in place of the
  # EvaluatorError in Location.stored; the assert_equal on the classes fails.
  def test_a_write_predicator_refuses_answers_its_error
    locations = ["l[-1]", "l.a", "s.a", "l[0].z", "x y", "a + b", "1", "l[nope]"]
    refusals = locations.map { D::Location.write(context(HOST), _1, 7).error }

    assert_equal [D::EvaluatorError], refusals.map(&:class).uniq
    assert_equal "l[-1]", refusals.first.source
  end

  # sabotage: answer true from Location.one_target?; the assert_equal fails.
  def test_text_that_is_not_one_assignment_target_is_refused
    refusals = ['"q"; y', "x = 1; y"].map { D::Location.write(context(HOST), _1, 7).error }

    assert_equal [D::InvalidLocation.new(location: '"q"; y'), D::InvalidLocation.new(location: "x = 1; y")], refusals
  end

  # sabotage: read a negative index as a miss (answer U for segment < 0) in
  # Location.read; the assert_equal on 20 fails.
  def test_the_prior_value_reads_a_negative_index_from_the_end_as_the_reference_does
    assert_equal([20, U, U], [[-1], [2], ["a"]].map { D::Location.read({ "l" => [10, 20] }, ["l", *_1]) })
  end

  KEYED = { "x" => { "a" => { "b" => [1, 2, 3] }, "k" => "kk" }, "l" => [10, 20], "m" => { "k" => 1 },
            "k" => "k", "i" => 2, "a" => { "b" => "k" } }.freeze

  # sabotage: answer true from Location.plain_keys?; the assert_equal fails, as
  # x.a.b[1 + 1] is written at ["x", "a", "b", 2].
  def test_a_computed_bracket_key_is_refused_as_the_reference_refuses_it
    locations = ["x.a.b[1 + 1]", "x[x.k].b[0]", "l[len('ab') - 2]", "x[-k]", "x[1.5]", "x[true]", "x[null]", "x[a.b]"]
    refusals = locations.map { D::Location.write(context(KEYED), _1, 7).error }

    assert_equal(locations.map { D::ComputedKey.new(location: _1) }, refusals)
    assert_equal "Cannot use computed expression as assignment target key", refusals.first.message
  end

  # sabotage: take a lit key only when it is an Integer (drop
  # "operand.is_a?(String) ||") in Location.lit_key_size; the assert_equal
  # fails.
  def test_a_string_literal_key_is_taken
    assert_equal([%w[m k], %w[m k]], ["m['k']", 'm["k"]'].map { D::Location.write(context(KEYED), _1, 7).path })
  end

  # sabotage: take a lit key only when it is a String (drop
  # "|| operand.is_a?(Integer)") in Location.lit_key_size; the assert_equal
  # fails.
  def test_an_integer_literal_key_is_taken
    assert_equal ["l", 0], D::Location.write(context(KEYED), "l[0]", 7).path
  end

  # sabotage: answer 1 for a negative literal ("? 1 : 1") in
  # Location.lit_key_size; the assert_equal fails, as the key is refused.
  def test_a_negative_integer_literal_key_is_taken
    assert_equal([["x", -1], ["l", 0]], ["x[-(1)]", "l[-0]"].map { D::Location.write(context(KEYED), _1, 7).path })
  end

  # sabotage: answer 0 for a load (when "load" then 0) in Location.key_size;
  # the assert_equal fails, as the key is refused.
  def test_an_identifier_key_is_taken_with_its_value
    paths = ["l[i]", "m[k]", "x[(k)]"].map { D::Location.write(context(KEYED), _1, 7).path }

    assert_equal [["l", 2], %w[m k], %w[x k]], paths
  end
end
