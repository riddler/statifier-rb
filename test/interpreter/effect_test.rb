# frozen_string_literal: true

require "test_helper"
require_relative "content_helper"

# What a block answers is plain data, frozen all the way down.
class EffectTest < Minitest::Test
  include ContentHelper

  # sabotage: append `effect` itself in place of Frozen.copy(effect)
  # in Content::Run#effect; the assert_equal fails.
  def test_every_effect_a_block_answers_is_deeply_frozen
    outcome = run_block(<<~XML)
      <log expr="m"/><send event="a" namelist="l m" delay="1s" idlocation="s"/>
      <send event="b"><content>[1, {'k': 2}]</content></send><cancel sendid="t"/>
    XML

    assert_equal([true] * 5, outcome.effects.map { Ractor.shareable?(_1) })
  end

  # sabotage: append the events themselves in place of their
  # Frozen.copy in Content::Run#raise_events; the assert_equal fails.
  def test_every_event_a_block_raises_is_deeply_frozen
    outcome = run_block(%(<raise event="r"/><log expr="nope"/>))

    assert_equal([true, true], outcome.raised.map { Ractor.shareable?(_1) })
  end

  # sabotage: answer Ractor.make_shareable(value) for every value in
  # Frozen.copy; the first assert_equal fails, as the host's hash
  # is frozen in place.
  def test_the_host_s_caller_context_is_carried_as_the_same_object_and_never_frozen
    context = { "token" => +"abc", "list" => [1] }
    outcome = run_block(%(<send event="a" delay="1s"/><cancel sendid="t"/>), with: { caller_context: context })

    assert_equal [false, false], [context.frozen?, context["list"].frozen?]
    assert_equal([true, true], outcome.effects.map { _1.caller_context.equal?(context) })
    assert_equal([true, true], outcome.effects.map { Ractor.shareable?(_1.with(caller_context: nil)) })
  end

  # sabotage: drop the caller_context line of Frozen.copy (answer
  # Ractor.make_shareable(value, copy: true) for every value); the
  # assert_equal fails, as the block raises in place of answering.
  def test_a_caller_context_that_cannot_be_shared_is_carried_without_raising
    callback = -> { :called }
    answered = begin
      run_block(%(<send event="a" delay="1s"/>), with: { caller_context: callback }).effects.map(&:caller_context)
    rescue StandardError => e
      e
    end

    assert_equal [callback], answered
  end

  # sabotage: pass copy: false in place of copy: true in
  # Frozen.copy; the first assert_equal fails, as the host's
  # datamodel value is frozen in place.
  def test_a_host_datamodel_value_an_effect_carries_is_copied_not_frozen_in_place
    host = { "h" => { "k" => +"v" } }
    outcome = run_block(%(<log expr="h"/>), host:)

    assert_equal [false, false], [host["h"].frozen?, host["h"]["k"].frozen?]
    assert_equal [{ "k" => "v" }, true], [outcome.effects.first.value, Ractor.shareable?(outcome.effects.first)]
  end
end
