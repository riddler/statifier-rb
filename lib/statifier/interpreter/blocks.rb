# frozen_string_literal: true

module Statifier
  module Interpreter
    # What a loop function answered: the {MachineState} it leaves and its
    # effects, in the order they were made.
    #
    # @api private
    Stepped = ::Data.define(:state, :effects) do
      # This step followed by `later`: `later`'s state, and both effect
      # lists in order.
      def then_step(later) = Stepped.new(state: later.state, effects: effects + later.effects)
    end

    # What a step runs against a {MachineState}, as the reference runs it
    # (`Statifier.Interpreter.Content.execute_block/3`, the binding of
    # `Statifier.Interpreter.Datamodel` and `ExitEntry.donedata/2` in
    # statifier-ex): a block of content, a `<data>` binding pass and a
    # final state's `<donedata>`, each read against the state as it stands
    # and each answering the state it leaves.
    #
    # A block runs through {Content.execute_block}: the datamodel it leaves,
    # its send state and the events it raised are kept, and with tracing on
    # a {Effect::Trace::ContentExecuted} follows its effects.
    #
    # @api private
    module Blocks
      module_function

      # One block run, owned by `owner`.
      #
      # @return [Stepped]
      def run_block(state, owner, content)
        stamp = Content::Stamp.new(owner:, **state.counters, caller_context: state.caller_context)
        outcome = Content.execute_block(state.context, content, stamp, state.sends)
        after = kept(state, outcome)
        trace = traced(after, Effect::Trace::ContentExecuted, owner:, c_indexes: outcome.executed)
        Stepped.new(state: after, effects: outcome.effects + trace)
      end

      # The state with what a block left kept: its datamodel, deeply frozen,
      # its send state and the events it raised, queued.
      def kept(state, outcome)
        state.with(datamodel: Ractor.make_shareable(outcome.context.data), sends: outcome.sends)
             .enqueue(*outcome.raised)
      end

      # Each of a state's `<onentry>` or `<onexit>` blocks (`kind`), in
      # document order, owned by its ordinal.
      #
      # @return [Stepped]
      def run_blocks(state, kind, index)
        state.machine.state(index).public_send(kind).each_with_index
             .reduce(Stepped.new(state:, effects: [])) do |acc, (block, ordinal)|
          acc.then_step(run_block(acc.state, { kind:, state_index: index, ordinal: }, block.content))
        end
      end

      # The content of the transition at `t_index`; nothing when it is nil.
      #
      # @return [Stepped]
      def run_transition_content(state, t_index)
        return Stepped.new(state:, effects: []) if t_index.nil?

        run_block(state, { kind: :transition, t_index: }, state.machine.transitions.fetch(t_index).content)
      end

      # What a `<data>` binding pass answered ({Datamodel::DataBinding}),
      # kept: each binding a {Effect::DatamodelChange} (its id the one-segment
      # path), each failure an `error.execution` (origin `{kind: :data,
      # d_index:}`).
      #
      # @return [Stepped]
      def bound(state, bound)
        after = bound.failures.reduce(state.with(datamodel: Ractor.make_shareable(bound.data))) do |acc, failure|
          acc.raise_failure({ kind: :data, d_index: failure.d_index }, failure.reason)
        end
        Stepped.new(state: after, effects: bound.changes.map { binding_change(state, _1) })
      end

      # The effect one binding answers.
      def binding_change(state, change)
        Frozen.copy(Effect::DatamodelChange.new(
                      location_path: [change.id], location_source: change.id, new_value: change.new_value,
                      prior_value: change.prior_value, d_index: change.d_index, c_index: nil, owner: nil,
                      **state.counters
                    ))
      end

      # `returnDoneEvent`'s data: the final state's `<donedata>` folded to
      # the value its `done.*` event carries, as `[state, data]`. None, or
      # an empty one, is no data; a `<content>` body is read as a `<send>`'s
      # is ({Send.text_data}); a `<content>` `expr` is evaluated, and a
      # failure raises `error.execution` (origin `{kind: :state,
      # state_index:}`) and is no data; `<param>`s are evaluated in order
      # against one context, each failure raising its own `error.execution`
      # (origin `{kind: :donedata_param, state_index:, param_index:}`) and
      # dropping that param.
      def donedata(state, index)
        donedata = state.machine.state(index).donedata
        return [state, Predicator::UNDEFINED] if donedata.nil? || (donedata.expr.nil? && donedata.params.empty?)
        return donedata_params(state, index, donedata.params) if donedata.expr.nil?

        donedata_content(state, index, donedata.expr)
      end

      # A `<donedata>` `<content>`, as {donedata}.
      def donedata_content(state, index, expr)
        return [state, Send.text_data(expr.value)] if expr.is_a?(Machine::Static)

        evaluated = Datamodel.evaluate(state.context, expr)
        return [state, evaluated.value] if evaluated.ok?

        [state.raise_failure({ kind: :state, state_index: index }, evaluated.error), Predicator::UNDEFINED]
      end

      # The `<donedata>` `<param>`s, as {donedata}.
      def donedata_params(state, index, params)
        context = state.context
        pairs = []
        params.each_with_index do |param, param_index|
          evaluated = Datamodel.evaluate(context, param.expr)
          next pairs << [param.name, evaluated.value] if evaluated.ok?

          state = state.raise_failure({ kind: :donedata_param, state_index: index, param_index: }, evaluated.error)
        end
        [state, Send.params_data(pairs)]
      end

      # The trace effect `klass` with `fields`, stamped with `state`'s
      # counters, as a one-element list; empty, and nothing built, when the
      # state does not trace. Every field is deeply frozen except an {Event},
      # already a frozen copy, whose host `caller_context` stays the host's
      # object.
      def traced(state, klass, **fields)
        return [] unless state.trace

        [klass.new(**fields.transform_values { _1.is_a?(Event) ? _1 : Ractor.make_shareable(_1) }, **state.counters)]
      end
    end
  end
end
