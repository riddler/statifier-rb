# frozen_string_literal: true

module Statifier
  module Interpreter
    # `mainEventLoop`'s inner loop and the outer body after a selection, as
    # the reference ports them (`Statifier.Interpreter.microstep/1`,
    # `macrostep/1` and `main_event_loop/1` in statifier-ex): rounds folded
    # to a stable configuration, the invoke pass, and the stop.
    #
    # Where this departs from the pseudocode, as the reference does:
    #
    # - The macrostep is bounded. The pseudocode lets it run forever; here
    #   the rounds spend a budget ({MachineState}'s `max_macrostep_rounds`,
    #   `:infinity` for none), and rounds that spend it stop where the last
    #   one left the state, the chart still running, and answer
    #   {Effect::BudgetExhausted} last. One budget spans the whole of
    #   {main_event_loop}, the invoke pass's re-entry included.
    # - A round is one pass of the inner loop, counted whether or not it
    #   moves anything, so a position between two rounds is a value.
    # - A selection's trace carries the microstep the selection ran in,
    #   before the microstep it starts.
    #
    # The invoke pass starts no invocation yet; it clears the states to
    # invoke and answers its {Effect::Trace::InvokePass} naming them.
    #
    # @api private
    module Macrostep
      module_function

      # `mainEventLoop`'s outer body after the caller's own selection: the
      # rounds run; then, while the chart runs, the invoke pass, and the
      # pseudocode's `continue` when the pass left the internal queue
      # non-empty, under the budget the rounds left; once the chart has
      # stopped, `exitInterpreter` ({Stop.exit_interpreter}).
      #
      # @return [Stepped]
      def main_event_loop(state, budget = state.max_macrostep_rounds, effects = [])
        outcome, state, folded, budget = fold(state, budget)
        effects += folded
        return stop(state, effects, outcome) unless state.running

        state, invoked = invoke_pass(state)
        after_invoke_pass(state, effects + invoked, outcome, budget)
      end

      # After the invoke pass: `continue` (the loop again, under the budget
      # left) when the pass left the queue non-empty and budget remains;
      # else the effect that ends the macrostep, {Effect::BudgetExhausted}
      # when the queue is still non-empty.
      #
      # @return [Stepped]
      def after_invoke_pass(state, effects, outcome, budget)
        waiting = !state.internal_queue.empty?
        return main_event_loop(state, budget, effects) if waiting && outcome == :quiescent && !spent?(budget)

        Stepped.new(state:, effects: effects + terminal(state, waiting ? :exhausted : outcome))
      end

      # The stop after the rounds: the effect that ended them, then
      # `exitInterpreter`'s.
      #
      # @return [Stepped]
      def stop(state, effects, outcome)
        exited = Stop.exit_interpreter(state)
        Stepped.new(state: exited.state, effects: effects + terminal(state, outcome) + exited.effects)
      end

      # The inner loop on its own, under a fresh budget: the rounds until
      # the macrostep is stable, the chart stops or the budget is spent,
      # then the one effect that ends it.
      #
      # @return [Stepped]
      def macrostep(state)
        outcome, state, effects, = fold(state, state.max_macrostep_rounds)
        Stepped.new(state:, effects: effects + terminal(state, outcome))
      end

      # The rounds, each charged against `budget`: `[outcome, state,
      # effects, budget left]`, `outcome` `:quiescent` (stable, or stopped)
      # or `:exhausted`. Reaching a stable configuration costs nothing beyond
      # the rounds already charged.
      def fold(state, budget)
        effects = []
        loop do
          return [:exhausted, state, effects, budget] if spent?(budget)

          quiescent, stepped = round(state)
          state = stepped.state
          effects += stepped.effects
          return [:quiescent, state, effects, budget] if quiescent

          budget -= 1 unless budget == :infinity
        end
      end

      # Whether `budget` (a count of rounds left, or `:infinity`) is spent.
      def spent?(budget) = budget != :infinity && budget.zero?

      # One pass of the inner `while running and not macrostepDone` loop:
      # the round counter advances, then the eventless transitions are
      # taken when any are enabled, else one internal event is taken and
      # the transitions it enables. `[quiescent, stepped]`: a round that
      # finds neither, or a chart no longer running, ends the macrostep.
      def round(state)
        state = state.begin_round
        return [true, Stepped.new(state:, effects: [])] unless state.running

        state, transitions, conds = select(state, nil)
        quiescent, stepped = transitions.empty? ? internal_round(state) : [false, run_selected(state, transitions, nil)]
        [quiescent, Stepped.new(state: stepped.state, effects: conds + stepped.effects)]
      end

      # The internal half of a round: the empty eventless selection's trace,
      # then the oldest queued event set as `_event` and the transitions it
      # enables taken; an empty queue ends the macrostep.
      def internal_round(state)
        event, rest = state.dequeue
        return [true, run_selected(state, [], nil)] if event.nil?

        dequeued = Blocks.traced(rest, Effect::Trace::EventDequeued, event:, from: :internal)
        state, transitions, conds = select(rest.put_event(event), event)
        head = Stepped.new(state:, effects: run_selected(rest, [], nil).effects + dequeued + conds)
        [false, head.then_step(run_selected(state, transitions, event))]
      end

      # A selection for `event` (nil for the eventless walk): `[state,
      # transitions, effects]`, the state with an `error.execution` queued
      # per condition that failed (origin `{kind: :transition, t_index:}`),
      # in walk order, and the round's {Effect::Trace::CondsEvaluated} when
      # it evaluated a written condition.
      def select(state, event)
        selected = selection(state, event)
        failed = selected.evaluations.select { _1.outcome == :error }
        state = failed.reduce(state) do |acc, one|
          acc.raise_failure({ kind: :transition, t_index: one.t_index }, one.reason)
        end
        [state, selected.transitions, conds_evaluated(state, selected.evaluations)]
      end

      # The {Selection} walk for `event`, the eventless one for nil.
      def selection(state, event)
        return Selection.select_eventless_transitions(state.snapshot, state.datamodel, clock: state.clock) if event.nil?

        Selection.select_transitions(state.snapshot, event.name, state.datamodel, clock: state.clock)
      end

      # The trace of a round's written conditions, none when it evaluated
      # none.
      def conds_evaluated(state, evaluations)
        return [] if evaluations.empty?

        Blocks.traced(state, Effect::Trace::CondsEvaluated, evaluations: evaluations.map(&:to_h).freeze)
      end

      # The tail every selection shares: its trace, then, when it took
      # anything, a new microstep that takes it.
      #
      # @return [Stepped]
      def run_selected(state, transitions, event)
        selected = Blocks.traced(state, Effect::Trace::TransitionsSelected,
                                 t_indexes: transitions.map(&:t_index).freeze, event:)
        return Stepped.new(state:, effects: selected) if transitions.empty?

        Stepped.new(state:, effects: selected).then_step(Step.microstep(state.begin_microstep, transitions))
      end

      # The invoke pass: the states entered since the last pass, in entry
      # order, cleared, with its trace. No invocation starts yet.
      def invoke_pass(state)
        trace = Blocks.traced(state, Effect::Trace::InvokePass, state_indexes: state.states_to_invoke, invoke_ids: [])
        [state.with(states_to_invoke: [].freeze), trace]
      end

      # The one effect that ends a macrostep: {Effect::Trace::MacrostepStable}
      # when it is stable with the chart running, nothing once it has
      # stopped, and {Effect::BudgetExhausted} when it spent its budget.
      def terminal(state, outcome)
        return exhausted(state) if outcome == :exhausted
        return [] unless state.running

        Blocks.traced(state, Effect::Trace::MacrostepStable, configuration: state.configuration)
      end

      # The {Effect::BudgetExhausted} of a macrostep that spent its budget.
      def exhausted(state)
        [Effect.frozen_copy(Effect::BudgetExhausted.new(configuration: state.configuration,
                                                        budget: state.max_macrostep_rounds,
                                                        pending_internal_events: state.internal_queue,
                                                        **state.counters))]
      end
    end
  end
end
