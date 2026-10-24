# frozen_string_literal: true

require "test_helper"
require_relative "content_helper"

# script: the program run against the block's datamodel, and its failures.
class ScriptTest < Minitest::Test
  include ContentHelper

  # sabotage: run the program against run.context.with(data: {}) in
  # Content.script; the assert_equal on y and x fails.
  def test_script_runs_its_program_against_the_block_s_datamodel
    outcome = run_block(%(<script>y = x + 1; x = y * 2</script><log expr="y"/>))

    assert_equal [2, 4], outcome.context.data.values_at("y", "x")
    assert_equal [2], outcome.effects.map(&:value)
  end

  # sabotage: answer nil in place of executed.error in Content.script; the
  # assert_equal on the raised names fails.
  def test_a_script_that_never_compiled_stops_the_block
    outcome = run_block(%(<script>this is not a program ]</script><raise event="never"/>))

    assert_equal ["error.execution"], raised_names(outcome)
    assert_equal "error", outcome.raised.first.data["kind"]
  end

  # sabotage: keep run.context in place of run.context.with(data:
  # executed.data) in Content.script; the assert_equal on x fails.
  def test_a_script_that_stops_keeps_the_writes_before_it
    outcome = run_block(%(<script>x = 9; y = nope.a; x = 10</script><raise event="never"/>))

    assert_equal [9, false], [outcome.context.data["x"], outcome.context.data.key?("y")]
    assert_equal ["error.execution"], raised_names(outcome)
    assert_equal "evaluator_error", outcome.raised.first.data["kind"]
  end
end
