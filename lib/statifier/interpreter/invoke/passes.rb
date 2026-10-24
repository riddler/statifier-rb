# frozen_string_literal: true

module Statifier
  module Interpreter
    module Invoke
      # The finalize and autoforward pass and the cancel on exit, as
      # {Invoke} says.
      #
      # @api private
      module Passes
        module_function

        # `for state in configuration: for inv in state.invoke: if
        # inv.invokeid == externalEvent.invokeid: applyFinalize(inv,
        # externalEvent); if inv.autoforward: send(inv.id, externalEvent)`,
        # run after `_event` is set and before selection, with its
        # {Effect::Trace::FinalizeAutoforward} last. The configuration is
        # walked in document order and each state's invocations in document
        # order; one that is not live is passed over. The two tests are
        # independent: a live invocation that matches and forwards does
        # both, its `<finalize>` first.
        #
        # @return [Array] `[state, effects]`
        def finalize_autoforward(state, event)
          return [state, trace(state, event, [], [])] if state.active_invocations.empty?

          passed, effects = state.configuration.reduce([state, []]) do |acc, index|
            state.machine.state(index).invoke.reduce(acc) { |inner, invoke| pass_one(inner, index, invoke, event) }
          end
          [passed, effects + trace(passed, event, finalized(state, event), forwarded(effects))]
        end

        # The live invocations whose id the event carries.
        def finalized(state, event) = state.active_invocations.values.select { _1 == event.invokeid }.uniq

        # The invocations the pass forwarded the event to, in order.
        def forwarded(effects) = effects.grep(Effect::Autoforward).map(&:invoke_id)

        # The pass's trace.
        def trace(state, event, finalized, forwarded)
          Blocks.traced(state, Effect::Trace::FinalizeAutoforward, event:, finalized:, forwarded:)
        end

        # One `<invoke>`'s body of the pass.
        def pass_one((state, effects), index, invoke, event)
          invoke_id = state.active_invocations[[index, invoke.index]]
          return [state, effects] if invoke_id.nil?

          stepped = invoke_id == event.invokeid ? finalize(state, index, invoke, event) : none(state)
          [stepped.state, effects + stepped.effects + forward(stepped.state, index, invoke, invoke_id, event)]
        end

        # A step that changes nothing.
        def none(state) = Stepped.new(state:, effects: [])

        # The {Effect::Autoforward} of an invocation that sets
        # `autoforward`.
        def forward(state, index, invoke, invoke_id, event)
          return [] unless invoke.autoforward

          [Effect::Autoforward.new(invoke_id:, state_index: index, event:, **state.counters)]
        end

        # `applyFinalize`: no `<finalize>` does nothing; an empty one writes
        # the returned values back ({auto_assign}); any other runs as a block
        # owned by `{kind: :finalize, state_index:, invoke_index:}`.
        #
        # @return [Stepped]
        def finalize(state, index, invoke, event)
          block = invoke.finalize
          return none(state) if block.nil?
          return auto_assign(state, index, invoke, event.data) if block.content.empty?

          Blocks.run_block(state, { kind: :finalize, state_index: index, invoke_index: invoke.index }, block.content)
        end

        # An empty `<finalize>`: each `namelist` entry and each `<param
        # location>` whose name the event's data, a map, carries is written
        # as by `<assign>` with that value, each write answering an
        # {Effect::DatamodelChange} in the order written. A write that fails
        # raises `error.execution` (origin `{kind: :finalize, state_index:,
        # invoke_index:}`) and leaves the other writes standing.
        #
        # @return [Stepped]
        def auto_assign(state, index, invoke, data)
          return none(state) unless data.is_a?(Hash)

          owner = { kind: :finalize, state_index: index, invoke_index: invoke.index }
          targets(invoke).select { data.key?(_1.name) }.reduce(none(state)) do |acc, param|
            acc.then_step(write(acc.state, param.expr.source, data[param.name], owner))
          end
        end

        # The `namelist` entries and `<param location>`s an empty
        # `<finalize>` may write, the ones that compiled.
        def targets(invoke)
          (invoke.namelist + invoke.params).select { _1.kind == :location && _1.expr.is_a?(Machine::Compiled) }
        end

        # One write of an empty `<finalize>`.
        #
        # @return [Stepped]
        def write(state, source, value, owner)
          written = Datamodel::Location.write(state.context, source, value)
          return none(state.raise_failure(owner, written.error)) unless written.ok?

          after = state.with(datamodel: Ractor.make_shareable(written.context.data))
          Stepped.new(state: after, effects: [Invoke.change(after, written, source, value, owner)])
        end

        # `for inv in s.invoke: cancelInvoke(inv)`: an {Effect::CancelInvoke}
        # per live invocation of the state at `index`, in document order,
        # each no longer live after it. Run after the state's `<onexit>`
        # blocks and before it leaves the configuration.
        #
        # @return [Stepped]
        def cancel_invocations(state, index)
          state.machine.state(index).invoke.reduce(none(state)) do |acc, invoke|
            acc.then_step(cancel_one(acc.state, index, invoke.index))
          end
        end

        # One invocation's `cancelInvoke(inv)`, nothing when it is not live.
        #
        # @return [Stepped]
        def cancel_one(state, index, invoke_index)
          key = [index, invoke_index]
          invoke_id = state.active_invocations[key]
          return none(state) if invoke_id.nil?

          after = state.with(active_invocations: state.active_invocations.except(key).freeze)
          Stepped.new(state: after, effects: [cancel_effect(after, invoke_id, index)])
        end

        # The {Effect::CancelInvoke}.
        def cancel_effect(state, invoke_id, index)
          Frozen.copy(Effect::CancelInvoke.new(invoke_id:, state_index: index, **state.counters,
                                               caller_context: state.caller_context))
        end
      end
    end
  end
end
