# frozen_string_literal: true

module Statifier
  module Interpreter
    # The specification's `exitInterpreter`, as the reference ports it
    # (`Statifier.Interpreter.exit_interpreter/1` in statifier-ex), with
    # `returnDoneEvent` an effect: {Effect::Done}, answered last.
    #
    # @api private
    module Stop
      module_function

      # `exitInterpreter`: every active state leaves in exit order, running
      # its `<onexit>` blocks and then cancelling its live invocations, with
      # no history recorded; the top-level final
      # among them, if any, yields the donedata, and with none the donedata
      # is nil. {Effect::Done} comes last, the status becomes `:done` and
      # the internal queue is emptied, taking any event the exits raised
      # with it, so a stopped chart is quiescent; the first
      # `error.execution` folding the donedata raised survives as
      # `donedata_error`. With tracing on an {Effect::Trace::ExitSet} comes
      # first and an {Effect::Trace::Done} just before {Effect::Done}.
      #
      # @return [Stepped]
      def exit_interpreter(state)
        order = state.configuration.reverse.freeze
        exited, effects, donedata, error = order.reduce([state, [], nil, nil]) { |acc, index| leave(acc, index) }
        trace = Blocks.traced(state, Effect::Trace::ExitSet, indexes: order, configuration: exited.configuration)
        done = done_effects(exited, donedata:, donedata_error: error, configuration: state.configuration)
        Stepped.new(state: exited.with(status: :done, internal_queue: [].freeze), effects: trace + effects + done)
      end

      # The {Effect::Trace::Done} (when tracing) and the {Effect::Done} of a
      # stop, the donedata and its error copied deeply frozen.
      def done_effects(exited, donedata:, donedata_error:, configuration:)
        fields = { donedata: Ractor.make_shareable(donedata, copy: true),
                   donedata_error: Ractor.make_shareable(donedata_error, copy: true), configuration: }
        Blocks.traced(exited, Effect::Trace::Done, **fields) + [Effect::Done.new(**fields, **exited.counters)]
      end

      # One state leaving at the stop: `[state, effects, donedata, error]`
      # after it.
      def leave((state, effects, donedata, error), index)
        left = Blocks.run_blocks(state, :onexit, index)
        left = left.then_step(Invoke::Passes.cancel_invocations(left.state, index))
        state = left.state.with(configuration: (left.state.configuration - [index]).freeze)
        donedata, error, state = collect_donedata(state, index) if top_level_final?(state.machine, index)
        [state, effects + left.effects, donedata, error]
      end

      # Whether the state is a final whose parent is the root.
      def top_level_final?(machine, index) = machine.final?(index) && machine.state(index).parent.zero?

      # The top-level final's donedata and the data of the first
      # `error.execution` folding it raised, `[data, error, state]`: the
      # queue is read either side of the fold, so an event already queued is
      # never taken for its own.
      def collect_donedata(state, index)
        before = state.internal_queue.size
        state, data = Blocks.donedata(state, index)
        raised = state.internal_queue.drop(before).find { _1.name == "error.execution" }
        [data, raised&.data, state]
      end
    end
  end
end
