# frozen_string_literal: true

require "test_helper"
require_relative "datamodel_helper"

# Datamodel.evaluate and evaluate_cond: predicator with In() as a host
# function, the reference's unbound policy, the host's clock, and every
# failure answered as a reason.
class EvaluateTest < Minitest::Test
  include DatamodelHelper

  # sabotage: evaluate against an empty Hash in place of context.data in
  # Datamodel.evaluate; the assert_equal on 5 fails.
  def test_a_compiled_expression_evaluates_against_the_datamodel
    evaluated = D.evaluate(context({ "x" => 2 }), compiled("x + 3"))

    assert_predicate evaluated, :ok?
    assert_equal 5, evaluated.value
  end

  # sabotage: answer expr.value.dup for a Static in Datamodel.evaluate; the
  # assert_same on the value fails.
  def test_a_static_value_comes_back_untouched
    value = { "a" => [1, 2] }.freeze

    assert_same value, D.evaluate(context, Internals::Machine::Static.new(value:)).value
  end

  # sabotage: answer error: nil for an Invalid in Datamodel.evaluate; the
  # assert_same on the error fails.
  def test_an_invalid_expression_answers_its_deferred_compile_refusal
    refusal = Internals::Compiler::Error.new(reason: :expression_compile_error, detail: {}, message: "m", location: nil)
    evaluated = D.evaluate(context, Internals::Machine::Invalid.new(error: refusal))

    refute_predicate evaluated, :ok?
    assert_same refusal, evaluated.error
  end

  # sabotage: set UNBOUND to :undefined in Datamodel; the refute_predicate
  # fails, as the comparison answers true.
  def test_an_unbound_root_fails_at_the_load
    evaluated = D.evaluate(context, compiled("nope === undefined"))

    refute_predicator_ok evaluated
    assert_instance_of D::EvaluatorError, evaluated.error
    assert_equal "nope === undefined", evaluated.error.source
    assert_instance_of Predicator::UndefinedVariableError, evaluated.error.error
  end

  # sabotage: seed "_event" with nil in SystemVariables.initial; the assert
  # on true fails.
  def test_event_is_declared_and_undefined_before_any_event
    answers = %w[_event _event.data].map { D.evaluate(context, compiled("#{_1} === undefined")).value }

    assert_equal [true, true], answers
  end

  # sabotage: answer configuration.include?(index + 1) in Datamodel.in_state;
  # the assert_equal on the answers fails.
  def test_in_answers_whether_a_state_is_active
    answers = ["In('s1')", "In('s2')", "In('nope')", "In(5)"].map { D.evaluate(context, compiled(_1)).value }

    assert_equal [true, false, false, false], answers
  end

  # sabotage: build the In function with the context's configuration
  # replaced by [2] in Context#options; the assert_equal fails.
  def test_in_reads_the_configuration_the_context_was_built_with
    answers = [[1], [2], []].map { D.evaluate(context(configuration: _1), compiled("In('s2')")).value }

    assert_equal [false, true, false], answers
  end

  # sabotage: give the In function an optional second parameter
  # (|state_id, _extra = nil|) in Datamodel.in_state; the refute_predicate
  # fails.
  def test_in_takes_exactly_one_argument
    evaluated = D.evaluate(context, compiled("In('s1', 's2')"))

    refute_predicator_ok evaluated
    assert_equal "Function In() expects 1 arguments, got 2", evaluated.error.error.message
  end

  # sabotage: drop clock: from Context#options; the assert_equal on the
  # year fails (the system clock answers today's).
  def test_the_clock_is_the_hosts_passed_for_the_call
    clock = -> { Predicator::DateTime.new(epoch_seconds: 0, microsecond: 0) }

    assert_equal 1970, D.evaluate(context(clock:), compiled("Date.year(Date.now())")).value
  end

  # sabotage: answer Evaluated.new(value: result.value, error: nil) in
  # Datamodel.evaluate; the refute_predicate fails.
  def test_a_failed_evaluation_answers_predicators_error_with_its_source
    evaluated = D.evaluate(context({ "x" => 1 }), compiled("x / 0"))

    refute_predicator_ok evaluated
    assert_equal ["x / 0", "division_by_zero"], [evaluated.error.source, evaluated.error.error.reason]
  end

  # sabotage: answer value: false for a nil cond in Datamodel.evaluate_cond;
  # the assert_equal fails.
  def test_no_condition_passes
    passed = D.evaluate_cond(context, nil)

    assert_equal [true, nil], [passed.value, passed.error]
  end

  # sabotage: return evaluated whatever its value in Datamodel.evaluate_cond;
  # the refute_predicate fails.
  def test_a_condition_that_is_not_boolean_fails_as_non_boolean
    evaluated = D.evaluate_cond(context({ "x" => 1 }), compiled("x"))

    refute_predicate evaluated, :ok?
    assert_equal D::NonBooleanCond.new(value: 1), evaluated.error
  end

  # sabotage: wrap a failed evaluation as NonBooleanCond in
  # Datamodel.evaluate_cond (drop "!evaluated.ok? ||"); the assert_instance_of
  # fails.
  def test_a_condition_that_fails_answers_the_evaluation_failure
    assert_instance_of D::EvaluatorError, D.evaluate_cond(context, compiled("nope")).error
  end

  # sabotage: test the value's truthiness (evaluated.value in place of
  # [true, false].include?(evaluated.value)) in Datamodel.evaluate_cond; the
  # assert_equal fails, as false fails as a NonBooleanCond.
  def test_a_boolean_condition_answers_its_value
    assert_equal([true, false], ["1 < 2", "1 > 2"].map { D.evaluate_cond(context, compiled(_1)).value })
  end

  # sabotage: answer `with(data: data)` in Context#bind; the assert_equal on
  # 9 fails.
  def test_bind_replaces_one_root_and_keeps_the_configuration
    bound = context({ "x" => 1 }).bind("x", 9)

    assert_equal [9, true], [D.evaluate(bound, compiled("x")).value, D.evaluate(bound, compiled("In('s1')")).value]
    assert_predicate bound.data, :frozen?
  end

  private

  def refute_predicator_ok(evaluated)
    refute_predicate evaluated, :ok?
    assert_nil evaluated.value
  end
end
