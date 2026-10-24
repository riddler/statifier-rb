# frozen_string_literal: true

module Statifier
  module Interpreter
    # The specification's `microstep`, `exitStates` and `enterStates` with
    # their content run, as the reference runs them
    # (`Statifier.Interpreter.microstep/2` and
    # `Statifier.Interpreter.ExitEntry` in statifier-ex). Which states leave
    # and enter, in which order, is {ExitEntry}'s; this module walks those
    # moves state by state against a {MachineState}: each exiting state runs
    # its `<onexit>` blocks while it is still active and then leaves, and
    # each entering state joins the configuration, binds its own `<data>`
    # on its first entry under late binding, runs its `<onentry>` blocks,
    # its initial and default-history content, and raises its completion
    # events, its parent's carrying the final state's `<donedata>`. The
    # blocks run through {Blocks}.
    #
    # @api private
    module Step
      module_function

      # `microstep`: the states the transitions leave exit, each
      # transition's content runs in the order given, and the states they
      # reach enter.
      #
      # @return [Stepped]
      def microstep(state, transitions)
        exited = exit_states(state, transitions)
        executed = execute_transition_content(exited.state, transitions)
        exited.then_step(executed).then_step(enter_states(executed.state, transitions))
      end

      # `exitStates`: the exit set leaves the states to invoke, the history
      # is recorded from the configuration before anything leaves, and each
      # state in exit order runs its `<onexit>` blocks and leaves. The
      # {Effect::Trace::ExitSet} comes first, stamped before the exits.
      #
      # @return [Stepped]
      def exit_states(state, transitions)
        moves = ExitEntry.exit_states(state.snapshot, transitions)
        state = state.with(states_to_invoke: (state.states_to_invoke - moves.states).freeze)
        trace = Blocks.traced(state, Effect::Trace::ExitSet, indexes: moves.states, configuration: moves.configuration)
        departures(Stepped.new(state: state.with(history: moves.history), effects: trace), moves.states)
      end

      # Each of `indexes` leaving in turn, after `stepped`.
      #
      # @return [Stepped]
      def departures(stepped, indexes)
        indexes.reduce(stepped) { |acc, index| acc.then_step(depart(acc.state, index)) }
      end

      # One state leaving: its `<onexit>` blocks, then out of the
      # configuration.
      #
      # @return [Stepped]
      def depart(state, index)
        left = Blocks.run_blocks(state, :onexit, index)
        left.with(state: left.state.with(configuration: (left.state.configuration - [index]).freeze))
      end

      # `executeTransitionContent`: each transition's content, in the order
      # given.
      #
      # @return [Stepped]
      def execute_transition_content(state, transitions)
        transitions.reduce(Stepped.new(state:, effects: [])) do |acc, transition|
          acc.then_step(Blocks.run_transition_content(acc.state, transition.t_index))
        end
      end

      # `enterStates`: each state of the entry set in entry order, with the
      # {Effect::Trace::EntrySet} first, stamped before any entry.
      #
      # @return [Stepped]
      def enter_states(state, transitions)
        moves = ExitEntry.enter_states(state.snapshot, transitions)
        trace = Blocks.traced(state, Effect::Trace::EntrySet, indexes: moves.states.map(&:index).freeze,
                                                              configuration: moves.configuration)
        moves.states.reduce(Stepped.new(state:, effects: trace)) do |acc, arrival|
          acc.then_step(arrive(acc.state, arrival))
        end
      end

      # One {ExitEntry::Arrival}: the state joins the configuration and the
      # states to invoke, binds its own `<data>` on its first entry, runs
      # its `<onentry>` blocks, its initial content and its default-history
      # content, and then raises its completions; a top-level final clears
      # `running` instead.
      #
      # @return [Stepped]
      def arrive(state, arrival)
        index = arrival.index
        stepped = enter(state, index)
        stepped = stepped.then_step(Blocks.run_blocks(stepped.state, :onentry, index))
        stepped = [arrival.initial_content, arrival.history_content].reduce(stepped) do |acc, t_index|
          acc.then_step(Blocks.run_transition_content(acc.state, t_index))
        end
        stepped.with(state: complete(stepped.state, arrival))
      end

      # The state with `index` active, among the states to invoke and
      # recorded as entered.
      def join(state, index)
        state.with(configuration: (state.configuration | [index]).sort.freeze,
                   states_to_invoke: (state.states_to_invoke | [index]).sort.freeze,
                   entered_states: (state.entered_states | [index]).sort.freeze)
      end

      # The state at `index` joined ({join}), with its own `<data>` bound
      # when this is its first entry ({Datamodel::DataBinding.enter_state}).
      #
      # @return [Stepped]
      def enter(state, index)
        joined = join(state, index)
        return Stepped.new(state: joined, effects: []) if state.entered_states.include?(index)

        Blocks.bound(joined, Datamodel::DataBinding.enter_state(joined.context, index))
      end

      # The completions an arrival raises (origin `{kind: :state,
      # state_index:}`, the final state's), or `running` cleared.
      def complete(state, arrival)
        return state.with(running: false) if arrival.stops

        arrival.completions.reduce(state) do |acc, completion|
          origin = { kind: :state, state_index: completion.final }
          next acc.raise_platform(completion.name, origin) unless completion.donedata

          acc, data = Blocks.donedata(acc, completion.final)
          acc.raise_platform(completion.name, origin, data:)
        end
      end
    end
  end
end
