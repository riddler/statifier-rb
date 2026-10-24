# frozen_string_literal: true

module Statifier
  module Interpreter
    # The invoke passes, as the reference ports them
    # (`run_invoke_pass`, `invoke_one`, `generate_invoke_id`,
    # `apply_invoke_passes`, `apply_finalize` and `auto_assign_finalize` in
    # `Statifier.Interpreter`, and `cancel_invocations_for_state` in
    # `Statifier.Interpreter.ExitEntry`, statifier-ex): starting the
    # invocations of the states a macrostep entered, the finalize and
    # autoforward pass an external event meets before its selection, and the
    # cancel of a state's live invocations as it exits.
    #
    # The core starts no service. Starting an invocation answers an
    # {Effect::Invoke} and records it live in the state's
    # `active_invocations`; forwarding an event answers an
    # {Effect::Autoforward} carrying the event whole; a state that exits
    # answers an {Effect::CancelInvoke} per live invocation it owns. Running
    # the service, delivering to it and turning what it answers into events
    # are the driver's. An event an invocation sent is an ordinary external
    # event here: its `invokeid` decides only which `<finalize>` runs.
    #
    # No host declares the invoke types it runs, so every invocation is
    # judged as the reference judges one in a session that declared none:
    # the effect is answered for any type, and only the built-in SCXML type
    # ({built_in_type?}) is recorded live.
    #
    # @api private
    module Invoke
      # The URI of the SCXML invoke type.
      SCXML_TYPE = "http://www.w3.org/TR/scxml/"

      # The spellings of the built-in type: none, the short form, and the
      # URI with and without its trailing slash.
      BUILT_IN_TYPES = [nil, "scxml", SCXML_TYPE, SCXML_TYPE.chomp("/")].freeze

      module_function

      # Whether the SCXML processor runs an invocation of `type` itself.
      def built_in_type?(type) = BUILT_IN_TYPES.include?(type)

      # `for state in statesToInvoke.sort(entryOrder): for inv in
      # state.invoke.sort(documentOrder): invoke(inv)`, then
      # `statesToInvoke.clear()`, with its {Effect::Trace::InvokePass} last.
      # One context is threaded through the pass, so an invocation's
      # arguments read an id an earlier one wrote to its `idlocation`. An
      # invocation whose start fails raises `error.execution` and answers
      # nothing; its siblings are unaffected.
      #
      # @return [Array] `[state, effects]`
      def invoke_pass(state)
        order = state.states_to_invoke
        passed, _context, effects = order.reduce([state, state.context, []]) do |acc, index|
          state.machine.state(index).invoke.reduce(acc) { |inner, invoke| invoke_one(inner, index, invoke) }
        end
        invoke_ids = live_ids(passed, effects)
        trace = Blocks.traced(passed, Effect::Trace::InvokePass, state_indexes: order, invoke_ids:)
        [passed.with(states_to_invoke: [].freeze), effects + trace]
      end

      # The ids of the invocations the pass left live, in the order it
      # started them.
      def live_ids(state, effects)
        effects.grep(Effect::Invoke).select { state.active_invocations[key(_1)] == _1.invoke_id }.map(&:invoke_id)
      end

      # The key an invocation is live under.
      def key(effect) = [effect.state_index, effect.invoke_index].freeze

      # `invoke(inv)`: the type, the source, the `namelist` and `<param>`
      # values in order, then `<content>`, the first failure abandoning this
      # invocation; then the id minted or read, `idlocation` written, the
      # invocation recorded live for the built-in type, and the effect,
      # after the write's {Effect::DatamodelChange}.
      #
      # @return [Array] `[state, context, effects]`
      def invoke_one((state, context, effects), index, invoke)
        origin = { kind: :invoke, state_index: index, invoke_index: invoke.index }
        resolved = Arguments.resolve(context, invoke)
        return [state.raise_failure(origin, resolved), context, effects] unless resolved.is_a?(Hash)

        state, invoke_id = mint(state, index, invoke)
        write = invoke.idlocation && Datamodel::Location.write(context, invoke.idlocation, invoke_id)
        return [state.raise_failure(origin, write.error), context, effects] if write && !write.ok?

        started(state, (write ? write.context : context), effects, invoke, resolved.merge(origin, invoke_id:, write:))
      end

      # An invocation whose arguments resolved and whose id is written:
      # recorded live for the built-in type, its effects answered.
      def started(state, context, effects, invoke, fields)
        state = state.with(datamodel: Ractor.make_shareable(context.data))
        state = record(state, fields) if built_in_type?(fields[:type])
        [state, context, effects + changes(state, invoke, fields) + [effect(state, invoke, fields)]]
      end

      # The state with the invocation live under its key.
      def record(state, fields)
        key = [fields[:state_index], fields[:invoke_index]].freeze
        state.with(active_invocations: state.active_invocations.merge(key => -fields[:invoke_id]).freeze)
      end

      # The {Effect::Invoke}.
      def effect(state, invoke, fields)
        Frozen.copy(Effect::Invoke.new(
                      **fields.slice(:invoke_id, :type, :src, :params, :content, :state_index, :invoke_index),
                      autoforward: invoke.autoforward, **state.counters, caller_context: state.caller_context
                    ))
      end

      # The `idlocation` write's {Effect::DatamodelChange}, when there was
      # one.
      def changes(state, invoke, fields)
        write = fields[:write]
        return [] unless write

        [change(state, write, invoke.idlocation, fields[:invoke_id], fields.slice(:kind, :state_index, :invoke_index))]
      end

      # A write no content node made, owned by the invocation (`{kind:
      # :invoke, ...}`) or by its empty `<finalize>` (`{kind: :finalize,
      # ...}`).
      def change(state, write, source, value, owner)
        Frozen.copy(Effect::DatamodelChange.new(
                      location_path: write.path, location_source: source, new_value: value,
                      prior_value: write.prior_value, d_index: nil, c_index: nil, owner:, **state.counters
                    ))
      end

      # `generate_invoke_id`: the author's id, which consumes no counter;
      # else `inv_` and the counter plus one, after the state's id and a dot
      # when the state has one. `[state, invoke_id]`.
      def mint(state, index, invoke)
        return [state, invoke.id] unless invoke.id.nil?

        counter = state.invoke_counter + 1
        owner = state.machine.state(index).id
        [state.with(invoke_counter: counter), owner.nil? ? "inv_#{counter}" : "#{owner}.inv_#{counter}"]
      end
    end
  end
end

require_relative "invoke/arguments"
require_relative "invoke/passes"
