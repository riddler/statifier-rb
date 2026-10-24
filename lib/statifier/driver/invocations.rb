# frozen_string_literal: true

module Statifier
  module Driver
    # The invocations a session holds and the child sessions behind them, as
    # the reference's session runs a built-in `scxml` invocation
    # (`Statifier.Session`, `Statifier.Session.Invocations` and
    # `Statifier.Invoke.Source` in statifier-ex), with a child's {State}
    # held in its parent's {Invocation} in place of a process. {Driver} says
    # what each does; what passes between a parent and its child is
    # {Mailbox}'s.
    #
    # A child runs as a work of its own ({Mailbox.within}): it starts on its
    # parent's clock and timer sequence, and its state, the timer sequence
    # it leaves, its effects and what it sent its parent go back to the
    # parent once it has run.
    #
    # @api private
    module Invocations
      # The fields of an error an invocation raises: no data and no send id.
      NO_FIELDS = { data: Predicator::UNDEFINED, sendid: nil }.freeze

      module_function

      # One invocation effect acted on: `[work, deferred effects]`.
      def perform(work, effect)
        case effect
        when Effect::Invoke then start(work, effect)
        when Effect::CancelInvoke then [cancel(work, effect.invoke_id), []]
        when Effect::Autoforward then [Mailbox.deliver(work, effect.invoke_id, effect.event), []]
        else [work, []]
        end
      end

      # An {Effect::Invoke}: a type other than the SCXML type raises
      # `error.execution`; content that is not markup, or does not compile,
      # raises `error.communication`; otherwise the child is started.
      # `[work, deferred effects]`.
      def start(work, effect)
        origin = { kind: :invoke, state_index: effect.state_index, invoke_index: effect.invoke_index }
        unless Interpreter::Invoke.built_in_type?(effect.type)
          return Routing.deliver_internal(work, :platform, "error.execution", origin, NO_FIELDS)
        end

        machine = effect.content.is_a?(String) ? compile(effect.content) : nil
        return Routing.deliver_internal(work, :platform, "error.communication", origin, NO_FIELDS) if machine.nil?

        [launch(work, effect, machine), []]
      end

      # Inline content markup compiled as the reference's
      # `Statifier.Invoke.Source` compiles it, a root with no namespace
      # accepted; nil when any stage refuses it.
      def compile(source)
        parsed = XML.parse(source)
        return nil unless parsed.ok?

        lowered = Lowering.lower(parsed.value, source)
        return nil unless lowered.ok?

        validated = Validator.validate(lowered.value, source, invoke_content_markup: true)
        return nil unless validated.ok?

        compiled = Compiler.compile(validated.value, warnings: validated.warnings)
        compiled.ok? ? compiled.value : nil
      end

      # The child started, recorded live under its invoke id, and run to a
      # stable configuration.
      def launch(work, effect, machine)
        child = child_start(work, effect, machine)
        work = work.put_invocation(Invocation.new(invoke_id: effect.invoke_id, autoforward: effect.autoforward == true,
                                                  completed: false, caller_context: effect.caller_context,
                                                  child: child.state))
        Mailbox.within(work, effect.invoke_id) { Run.drain(Run.perform(_1, child.effects)) }
      end

      # The child's start: its {State} and the effects its start answered,
      # as a {Interpreter::Stepped}. Its session id is its parent's, a dot
      # and the invoke id.
      def child_start(work, effect, machine)
        session_id = -"#{work.state.session_id}.#{effect.invoke_id}"
        started = Interpreter::Loop.initialize(machine, **start_options(work, session_id, effect.params, machine))
        state = Calls.fresh(started.state, session_id, work.state.send_types).with(invoked_as: effect.invoke_id)
        Interpreter::Stepped.new(state:, effects: started.effects)
      end

      # What the child starts with: its parent's registered types, their
      # `_ioprocessors` entries asked for its own session id, its parent's
      # trace flag, and its datamodel seeded ({seed}).
      def start_options(work, session_id, params, machine)
        types = work.state.send_types
        { session_id:, clock: work.clock, datamodel: seed(params, machine), trace: work.machine_state.trace,
          send_types: (types unless types.empty?), ioprocessors: Calls.entries(work.processors, types, session_id),
          routes: Calls.own_routes(session_id, parent: true) }
      end

      # The reference's `Invocations.seed_datamodel/2`: the params a root
      # `<data>` of the child names, the rest dropped.
      def seed(params, machine)
        return {} unless params.is_a?(Hash)

        params.slice(*machine.state(0).data.map { machine.data_elements.fetch(_1).id })
      end

      # An {Effect::CancelInvoke}: the invocation retired, then its child
      # stopped, its active states' `<onexit>` handlers run, its effects
      # reported and what it sent its parent discarded. An invocation whose
      # child already said it completed is left for its done event, and an
      # id that names nothing live is a no-op.
      def cancel(work, invoke_id)
        invocation = work.state.invocations[invoke_id]
        return work if invocation.nil? || invocation.completed

        work = work.drop_invocation(invoke_id)
        return work unless invocation.child.machine_state.running

        Mailbox.absorb(work, stop(work, work.synced(invocation.child).with(cancelled: true)))
      end

      # The cancelled child's run: the reference's `Interpreter.cancel/1`
      # and the effects it answered acted on.
      def stop(work, child)
        handled = Interpreter::Loop.cancel(child.machine_state)
        Run.perform(Run.begin_call(child, work.processors, work.clock).with_machine(handled.state), handled.effects)
      end
    end
  end
end
