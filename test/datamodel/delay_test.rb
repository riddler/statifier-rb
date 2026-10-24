# frozen_string_literal: true

require "test_helper"
require_relative "datamodel_helper"

# Datamodel::Delay.milliseconds: a delay read through predicator's duration
# parser, as the reference reads it.
class DelayTest < Minitest::Test
  include DatamodelHelper

  # Each delay text with the reference's answer at its tag
  # (Statifier.Duration.to_ms/1), nil where it refuses.
  TEXTS = {
    "1s" => 1_000, "1.5s" => 1_500, ".5s" => 500, "100ms" => 100, "2m" => 120_000, "1h30m" => 5_400_000,
    "1w" => 604_800_000, "1mo" => 2_592_000_000, "1y" => 31_536_000_000, "0s" => 0, "0.0001s" => nil,
    "" => nil, "1 s" => nil, "-1s" => nil, "5" => nil, "1x" => nil, "1.5ms" => nil, ".5" => nil
  }.freeze

  # sabotage: drop the leading-dot rewrite in Delay.parsed; the assert_equal
  # fails on ".5s".
  def test_delay_text_reads_as_the_reference_reads_it
    answers = TEXTS.keys.to_h { [_1, D::Delay.milliseconds(_1).value] }

    assert_equal TEXTS, answers
  end

  # sabotage: carry the rewritten text ("0#{text}") in the refusal in
  # Delay.parsed; the assert_equal fails.
  def test_refused_text_is_an_invalid_delay_carrying_the_text_as_given
    assert_equal D::InvalidDelay.new(value: ".x"), D::Delay.milliseconds(".x").error
  end

  # sabotage: weigh a month as 31 days in Delay::WEIGHTS; the assert_equal
  # fails.
  def test_a_duration_value_is_summed
    duration = Predicator::Duration.new(months: 1, days: 2)

    assert_equal 2_592_000_000 + 172_800_000, D::Delay.milliseconds(duration).value
  end

  # sabotage: answer an InvalidDelay for a Hash in Delay.milliseconds; the
  # assert_equal fails.
  def test_a_map_is_zero_as_the_reference_reads_it_and_anything_else_is_refused
    values = [{ "days" => 1 }, Predicator.evaluate!("Date.now()"), Predicator.evaluate!("#2024-01-15#")]

    assert_equal([0, 0, 0], values.map { D::Delay.milliseconds(_1).value })
    assert_equal([D::InvalidDelay.new(value: 5), D::InvalidDelay.new(value: [1])],
                 [5, [1]].map { D::Delay.milliseconds(_1).error })
  end
end
