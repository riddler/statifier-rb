# frozen_string_literal: true

require "test_helper"
require_relative "content_helper"

# What a block answers is plain data, frozen all the way down.
class EffectTest < Minitest::Test
  include ContentHelper

  # sabotage: append `effect` without Ractor.make_shareable in
  # Content::Run#effect; the assert_equal fails.
  def test_every_effect_a_block_answers_is_deeply_frozen
    outcome = run_block(<<~XML)
      <log expr="m"/><send event="a" namelist="l m" delay="1s" idlocation="s"/>
      <send event="b"><content>[1, {'k': 2}]</content></send><cancel sendid="t"/>
    XML

    assert_equal([true] * 5, outcome.effects.map { Ractor.shareable?(_1) })
  end

  # sabotage: append the events without Ractor.make_shareable in
  # Content::Run#raise_events; the assert_equal fails.
  def test_every_event_a_block_raises_is_deeply_frozen
    outcome = run_block(%(<raise event="r"/><log expr="nope"/>))

    assert_equal([true, true], outcome.raised.map { Ractor.shareable?(_1) })
  end
end
