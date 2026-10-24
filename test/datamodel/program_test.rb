# frozen_string_literal: true

require "test_helper"
require_relative "datamodel_helper"

# Datamodel.execute: a <script> program with the reference's outcome. A
# store into a system root the datamodel holds stops the run at the attempt;
# the writes before any stop are kept; a system root the program creates
# fresh is never kept and fails the run.
class ProgramTest < Minitest::Test
  include DatamodelHelper

  # sabotage: answer Executed.new(data: before, ...) in Program.outcome; the
  # assert_equal on 1 fails.
  def test_a_successful_program_keeps_its_write
    executed = D.execute(context({ "x" => nil }), program("x = 1;"))

    assert_predicate executed, :ok?
    assert_equal 1, executed.data["x"]
    assert_predicate executed.data, :frozen?
  end

  # sabotage: drop the NOTE call from Stores.piece (answer [instruction]); the
  # assert_equal on x fails, as nothing records the write before the stop.
  def test_a_mid_program_failure_keeps_the_earlier_write_and_reports_the_error
    executed = D.execute(context({ "x" => nil, "y" => nil }), program("x = 1; y = nope + 1;"))

    assert_instance_of Predicator::UndefinedVariableError, executed.error.error
    assert_equal "x = 1; y = nope + 1;", executed.error.source
    assert_equal({ "x" => 1, "y" => nil }, authored(executed.data))
  end

  # sabotage: keep only roots the datamodel held (other.to_h.slice(*before.keys))
  # in Program.outcome; the assert_equal on 42 fails.
  def test_a_program_may_create_a_root_no_datamodel_declared
    assert_equal 42, D.execute(context, program("newvar = 42;")).data["newvar"]
  end

  # sabotage: answer [instruction, ...] (the NOTE piece) for a protected root
  # in Stores.piece; the assert_nil on x fails, as the run goes on.
  def test_a_system_variable_write_halts_the_program_at_the_attempt
    executed = D.execute(context({ "x" => nil }), program("_event = 1; x = 2;"))

    assert_equal D::SystemVariable.new(root: "_event"), executed.error
    assert_nil executed.data["x"]
    assert_same U, executed.data["_event"]
  end

  # sabotage: answer nil for a halt (return nil if halted) in Program.failure;
  # the assert_equal on the error fails, as nothing reports the halt.
  def test_a_write_then_restore_of_a_system_variable_is_caught
    executed = D.execute(context, program("_name = 'other'; _name = 'chart';"))

    assert_equal D::SystemVariable.new(root: "_name"), executed.error
  end

  # sabotage: protect no root (protected_roots = []) in Program.run; the
  # assert_nil on seen fails.
  def test_a_later_statement_does_not_observe_the_refused_write
    executed = D.execute(context({ "seen" => nil }), program("_name = 'other'; seen = _name;"))

    assert_equal D::SystemVariable.new(root: "_name"), executed.error
    assert_nil executed.data["seen"]
  end

  # sabotage: delete the "failure ||= SystemVariable.new(...)" line in
  # Program.outcome; the assert_equal on the error fails.
  def test_a_program_created_system_root_is_never_kept_and_fails_the_run
    executed = D.execute(context({ "x" => nil }), program("_created = 1; x = 2;"))

    assert_equal D::SystemVariable.new(root: "_created"), executed.error
    refute executed.data.key?("_created")
    assert_equal 2, executed.data["x"]
  end

  # sabotage: name system.map(&:first).max in Program.outcome; the
  # assert_equal on "_a" fails.
  def test_several_created_system_roots_name_the_first_in_sort_order
    assert_equal "_a", D.execute(context, program("_b = 1; _a = 2;")).error.root
  end

  # sabotage: let the created-root failure win (failure = SystemVariable...
  # without ||=) in Program.outcome; the assert_equal on "_event" fails.
  def test_a_protected_halt_names_its_root_over_a_created_one
    executed = D.execute(context({ "x" => nil }), program("x = 1; _c = 1; _event = 2; x = 3;"))

    assert_equal [D::SystemVariable.new(root: "_event"), 1], [executed.error, executed.data["x"]]
    refute executed.data.key?("_c")
  end

  # sabotage: answer Executed.new(data: context.data, error: nil) for an
  # Invalid in Datamodel.execute; the assert_same fails.
  def test_an_invalid_program_answers_its_compile_refusal_and_writes_nothing
    refusal = Internals::Compiler::Error.new(reason: :expression_compile_error, detail: {}, message: "m", location: nil)
    executed = D.execute(context({ "x" => 1 }), Internals::Machine::Invalid.new(error: refusal))

    assert_same refusal, executed.error
    assert_equal({ "x" => 1 }, authored(executed.data))
  end

  # sabotage: build the guarded list without moving the jumps (answer
  # pieces.flatten(1)) in Stores.guarded; the assert_equal on the rows fails.
  def test_the_reference_outcome_for_programs_with_branches_and_loops
    REFERENCE_ROWS.each do |source, error, authored_data|
      executed = D.execute(context({ "x" => nil, "y" => nil }), program(source))

      assert_equal [error, authored_data], [reason_of(executed.error), authored(executed.data)], source
    end
  end

  # Each program with the reference's answer at its tag (the reference's
  # Statifier.Evaluator.execute/2, run against the same datamodel): the
  # error, as the system root named or predicator's error class, and the
  # author roots the run left.
  REFERENCE_ROWS = [
    ["if (true) { x = 5; _name = 1 } else { y = 1 }; y = 9", "_name", { "x" => 5, "y" => nil }],
    ["if (false) { x = 5; _name = 1 } else { y = 1 }; x = 9", nil, { "x" => 9, "y" => 1 }],
    ["x = 0; while (x < 3) { x = x + 1 }; y = x", nil, { "x" => 3, "y" => 3 }],
    ["x = 0; while (x < 3) { x = x + 1; if (x == 2) { _event = x } }; y = x", "_event", { "x" => 2, "y" => nil }],
    ["x = {a: 1}; x.b = 2; x.a = x.a + 1", nil, { "x" => { "a" => 2, "b" => 2 }, "y" => nil }],
    ["x = [1, 2]; x[5] = 3", nil, { "x" => [1, 2, U, U, U, 3], "y" => nil }],
    ["x = 1; x.a = 2", "EvaluationError", { "x" => 1, "y" => nil }],
    ["x = 1; x = 2; x = 3; _ioprocessors.a = 1", "_ioprocessors", { "x" => 3, "y" => nil }],
    ["x = 1; _zz = 1; y = 1/0", "EvaluationError", { "x" => 1, "y" => nil }],
    ["x = In('s1'); y = In('s2')", nil, { "x" => true, "y" => false }],
    ["x = 0; while (x < 100000) { x = x + 1 }", "EvaluationError", { "x" => 10_001, "y" => nil }]
  ].freeze

  private

  def reason_of(error)
    case error
    when nil then nil
    when D::SystemVariable then error.root
    else error.error.class.name.split("::").last
    end
  end
end
