# frozen_string_literal: true

require "test_helper"
require_relative "loop_helper"

# The macrostep's rounds, their counter and the round budget.
class MacrostepTest < Minitest::Test
  include LoopHelper

  # sabotage: answer `budget.negative?` in place of `budget.zero?` in
  # Macrostep.spent?; the assert_equal on the round fails (4).
  def test_a_macrostep_that_spends_its_round_budget_stops_where_it_was_and_keeps_running
    started = start(<<~XML, max_macrostep_rounds: 3)
      <state id="a"><onentry><raise event="r"/></onentry><transition event="r" target="a"/></state>
    XML
    exhausted = started.effects.last

    assert_instance_of E::BudgetExhausted, exhausted
    assert_equal [3, 3, [0, 1]], [exhausted.budget, exhausted.round, exhausted.configuration]
    assert_equal ["r"], exhausted.pending_internal_events.map(&:name)
    assert started.state.running
  end

  # sabotage: answer false from Macrostep.spent?; the first assert_equal fails,
  # as the one-round budget never ends the macrostep.
  def test_a_budget_of_one_ends_a_two_round_macrostep_and_an_infinite_one_never_ends_one
    started = start(%(<state id="a"><onentry><raise event="r"/></onentry><transition event="r" target="b"/></state>
                      <state id="b"/>), max_macrostep_rounds: 1)
    unbounded = start(%(<state id="a"/>), max_macrostep_rounds: :infinity)

    assert_equal [1], started.effects.grep(E::BudgetExhausted).map(&:budget)
    assert_equal %w[b], active(started.state)
    assert_empty unbounded.effects.grep(E::BudgetExhausted)
  end

  # sabotage: drop `state = state.begin_round` in Macrostep.round; the
  # assert_equal fails (round 0).
  def test_the_round_counter_counts_every_pass_the_empty_last_one_included
    started = start(%(<state id="a"><transition target="b"/></state><state id="b"/>))

    assert_equal [1, 2, 2], [started.state.macrostep, started.state.microstep, started.state.round]
  end

  # sabotage: answer `effects` without `terminal(state, outcome)` in
  # Macrostep.macrostep; the assert_equal on the kinds fails.
  def test_macrostep_folds_one_macrostep_under_a_fresh_budget_and_ends_it
    started = start(%(<state id="a"><transition event="go" target="b"/></state><state id="b"/>), trace: true)
    queued = started.state.raise_internal("go", { kind: :state, state_index: 0 }).begin_macrostep
    stepped = Internals::Interpreter::Macrostep.macrostep(queued)

    assert_equal %w[b], active(stepped.state)
    assert_equal "T.MacrostepStable", kinds(stepped.effects).last
  end
end
