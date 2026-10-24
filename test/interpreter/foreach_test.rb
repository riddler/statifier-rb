# frozen_string_literal: true

require "test_helper"
require_relative "content_helper"

# foreach: the iteration over a copy, the item and index binding, and the
# failures that stop it.
class ForeachTest < Minitest::Test
  include ContentHelper

  F = Statifier::Interpreter::Foreach

  # sabotage: bind position + 1 in place of position in
  # Foreach.bind_iteration; the assert_equal on the logs fails.
  def test_foreach_binds_the_item_and_the_index_on_each_iteration
    outcome = run_block(<<~XML)
      <foreach array="l" item="it" index="ix"><assign location="x" expr="x + it"/><log expr="[ix, it]"/></foreach>
    XML

    assert_equal [[0, 1], [1, 2], [2, 3]], effects_of(outcome, E::Log).map(&:value)
    assert_equal [7, 3, 2], outcome.context.data.values_at("x", "it", "ix")
  end

  # sabotage: bind Datamodel.evaluate(at.context, node.array).value[i] in
  # place of value in Foreach.execute; the assert_equal on the logs fails.
  def test_foreach_iterates_the_list_as_it_was_when_the_loop_began
    outcome = run_block(%(<foreach array="l" item="it"><assign location="l" expr="[]"/><log expr="it"/></foreach>))

    assert_equal [1, 2, 3], outcome.effects.grep(E::Log).map(&:value)
  end

  # sabotage: answer `context` unchanged from Foreach.declare; the
  # assert_equal on the declared names fails.
  def test_an_empty_list_still_declares_the_item_and_the_index
    outcome = run_block(%(<foreach array="[]" item="fresh" index="fi"><raise event="never"/></foreach>))

    assert_equal [Predicator::UNDEFINED, Predicator::UNDEFINED], outcome.context.data.values_at("fresh", "fi")
    assert_empty outcome.raised
  end

  # sabotage: answer nil in place of the NAME.match? line of
  # Foreach.illegal_name; the
  # assert_equal on the reason fails.
  def test_an_item_that_is_not_a_bare_name_stops_the_block
    outcome = run_block(%(<foreach array="l" item="1bad"><raise event="never"/></foreach><raise event="never2"/>))

    assert_equal [F::IllegalItemName.new(name: "1bad")], reasons(outcome)
    refute outcome.context.data.key?("1bad")
  end

  # sabotage: pass IllegalItemName for the index in Foreach.iterated; the
  # assert_equal on the reason fails.
  def test_an_index_that_is_not_a_bare_name_stops_the_block
    outcome = run_block(%(<foreach array="l" item="it" index="i-x"><raise event="never"/></foreach>))

    assert_equal [F::IllegalIndexName.new(name: "i-x")], reasons(outcome)
    refute outcome.context.data.key?("it")
  end

  # sabotage: drop the start_with?("_") line of Foreach.illegal_name; the
  # assert_equal on the reason fails, as the name passes as a bare name.
  def test_an_item_naming_a_system_variable_stops_the_block
    outcome = run_block(%(<foreach array="l" item="_x"><raise event="never"/></foreach>))

    assert_equal [DM::SystemVariable.new(root: "_x")], reasons(outcome)
  end

  # sabotage: answer evaluated.value whatever it is in Foreach.iterated; the
  # assert_equal on the reason fails (a Hash iterates as pairs).
  def test_an_array_that_is_not_a_list_stops_the_block
    outcome = run_block(%(<foreach array="m" item="it"><raise event="never"/></foreach>))

    assert_equal [F::NotIterable.new(value: { "a" => 1 })], reasons(outcome)
  end

  # sabotage: answer [] in place of evaluated.error in Foreach.iterated; the
  # assert_equal on the raised names fails, as the empty loop succeeds.
  def test_an_array_that_fails_to_evaluate_stops_the_block
    outcome = run_block(%(<foreach array="nope" item="it"><raise event="never"/></foreach><raise event="never2"/>))

    assert_equal ["error.execution"], raised_names(outcome)
    assert_instance_of DM::EvaluatorError, outcome.raised.first.reason
  end

  # sabotage: answer [run, reason] in place of [after, reason] on the break
  # in Foreach.execute; the assert_equal on x fails, as the earlier
  # iterations' writes are lost.
  def test_a_body_failure_keeps_earlier_iterations_writes_and_names_the_inner_node
    outcome = run_block(<<~XML)
      <foreach array="l" item="it"><assign location="x" expr="it"/><if cond="it == 2"><assign location="zz" expr="0"/></if></foreach>
      <raise event="never"/>
    XML

    assert_equal 2, outcome.context.data["x"]
    assert_empty outcome.effects
    inner = C::NestedContent.new(c_index: 3, reason: DM::UnboundLocation.new(location: "zz"))
    assert_equal [C::NestedContent.new(c_index: 2, reason: inner)], reasons(outcome)
  end
end
