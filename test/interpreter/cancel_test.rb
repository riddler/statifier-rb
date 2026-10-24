# frozen_string_literal: true

require "test_helper"
require_relative "content_helper"

# cancel: the effect naming a send id, and its failure.
class CancelTest < Minitest::Test
  include ContentHelper

  # sabotage: pass ordinal: sends.timer_counter + 1 in Send.execute_cancel;
  # the first assert_equal fails.
  def test_cancel_answers_the_send_id_with_an_ordinal
    outcome = run_block(%(<send event="a" delay="1s" idlocation="m.k"/><cancel sendidexpr="m.k"/><cancel sendid="t"/>))

    assert_equal([["send_1", 1], ["send_1", 2], ["t", 3]],
                 outcome.effects.grep_v(E::DatamodelChange).map { [_1.send_id, _1.ordinal] })
    assert_equal({ "a" => 1, "k" => "send_1" }, outcome.context.data["m"])
  end

  # sabotage: drop the guard `return failed(...) unless evaluated.ok?` from
  # Send.execute_cancel; the assert_equal on the raised names fails.
  def test_a_cancel_whose_sendidexpr_fails_stops_the_block
    outcome = run_block(%(<cancel sendidexpr="nope"/><raise event="never"/>))

    assert_equal [["error.execution"], 0], [raised_names(outcome), outcome.sends.timer_counter]
    assert_empty outcome.effects
  end
end
