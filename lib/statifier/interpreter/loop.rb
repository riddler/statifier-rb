# frozen_string_literal: true

module Statifier
  module Interpreter
    # What {Loop.handle_event} and {Loop.deliver_internal} answered: the
    # {MachineState} and effects of the step, or, as `error`,
    # `:not_running` for a chart that has stopped, with the state given
    # back unchanged and no effects.
    #
    # @api private
    Handled = ::Data.define(:state, :effects, :error) do
      # @return [Boolean] whether the step ran
      def ok? = error.nil?
    end

    # The specification's `interpret` and `mainEventLoop`, ported as the
    # reference ports them (`Statifier.Interpreter` in statifier-ex): three
    # entry points over a {MachineState}, each answering the state it leaves
    # with its effects. {initialize} starts a chart, {handle_event} takes one
    # external event and {deliver_internal} queues one event on the internal
    # queue (the driver's door for a send to `#_internal`, or for a delivery
    # failure it found); each then runs the macrostep ({Macrostep}) to a
    # stable configuration, or to the chart stopping ({Stop}).
    #
    # The outer `while running` loop is the caller's, as in the reference:
    # the core takes one external event per call, and the driver keeps the
    # external events still waiting.
    #
    # Starting a chart answers {Effect::DatamodelInit} first, then a
    # {Effect::DatamodelChange} per `<data>` that binds. With the state's
    # `trace` set, the loop answers the reference's trace effects in its
    # order.
    #
    # Before an external event's selection the finalize and autoforward
    # pass runs over the live invocations ({Invoke::Passes}); {cancel} is
    # the specification's cancel path, which stops a running chart.
    #
    # @api private
    module Loop
      module_function

      # `interpret`: a fresh {MachineState} over `machine` (the options are
      # {MachineState.fresh}'s), its datamodel initialized, the `<script>`
      # children of `<scxml>` run in document order, the initial states
      # entered and the macrostep run. This is macrostep 1, and the initial
      # entry its microstep 1. `clock` is the host's clock for the call.
      #
      # @return [Stepped]
      def self.initialize(machine, session_id:, clock: nil, **)
        state = MachineState.fresh(machine, session_id:, **).begin_macrostep.begin_microstep.with(clock:)
        bound = initialize_datamodel(state)
        scripts = bound.then_step(run_global_scripts(bound.state))
        entered = scripts.then_step(Step.enter_states(scripts.state, [initial_transition(machine)]))
        entered.then_step(Macrostep.main_event_loop(entered.state))
      end

      # `mainEventLoop`'s external-event body: a new macrostep stamped with
      # the event's `caller_context`, `_event` set, the transitions the
      # event enables selected and taken, then the macrostep run. The
      # answered state's `last_selection` says whether the event selected a
      # transition. `event` is an {Event}, copied before it is frozen except
      # its `caller_context`, which the state carries as the same object.
      #
      # @return [Handled]
      def handle_event(state, event, clock: nil)
        return Handled.new(state:, effects: [], error: :not_running) unless state.running

        event = Effect.frozen_copy(event)
        state = state.begin_macrostep.with(caller_context: event.caller_context, clock:)
        dequeued = Blocks.traced(state, Effect::Trace::EventDequeued, event:, from: :external)
        taken = take(state.put_event(event), event)
        Handled.new(state: taken.state, effects: dequeued + taken.effects, error: nil)
      end

      # The finalize and autoforward pass, the event's selection and
      # the macrostep after it, with `last_selection` written.
      #
      # @return [Stepped]
      def take(state, event)
        state, passes = Invoke::Passes.finalize_autoforward(state, event)
        state, transitions, conds = Macrostep.select(state, event)
        ran = Macrostep.run_selected(state, transitions, event)
        looped = ran.then_step(Macrostep.main_event_loop(ran.state))
        Stepped.new(state: looped.state.with(last_selection: transitions.empty? ? :none : :selected),
                    effects: passes + conds + looped.effects)
      end

      # `mainEventLoop`'s cancel path: `running` cleared, then
      # `exitInterpreter` ({Stop.exit_interpreter}), with no caller context,
      # since a cancel has no sending caller. A stopped chart answers
      # `:not_running`, its state unchanged.
      #
      # @return [Handled]
      def cancel(state)
        return Handled.new(state:, effects: [], error: :not_running) unless state.running

        exited = Stop.exit_interpreter(state.with(running: false, caller_context: nil))
        Handled.new(state: exited.state, effects: exited.effects, error: nil)
      end

      # The door back onto the internal queue: one event of `kind`
      # (`:internal` or `:platform`) named `name`, its cause `origin` and
      # the counters as they stand, queued as an in-loop raise would queue
      # it, then the macrostep run. `options` are the event's `data:` and
      # `sendid:`, and `clock:`, the host's clock for the call. The driver
      # routes a send to `#_internal` here, and an `error.communication` for
      # a send it could not deliver.
      #
      # @return [Handled]
      def deliver_internal(state, kind, name, origin, **options)
        return Handled.new(state:, effects: [], error: :not_running) unless state.running

        raised = state.with(clock: options[:clock])
                      .public_send(kind == :internal ? :raise_internal : :raise_platform, name, origin,
                                   **options.except(:clock))
        looped = Macrostep.main_event_loop(raised)
        Handled.new(state: looped.state, effects: looped.effects, error: nil)
      end

      # The datamodel initialized: {Effect::DatamodelInit} with every
      # `<data>` id declared, then the binding of what binds when the chart
      # starts ({Datamodel::DataBinding.start}).
      #
      # @return [Stepped]
      def initialize_datamodel(state)
        context = state.context
        init = Effect::DatamodelInit.new(datamodel: Datamodel::DataBinding.seed(context), **state.counters)
        Stepped.new(state:, effects: [Effect.frozen_copy(init)])
               .then_step(Blocks.bound(state, Datamodel::DataBinding.start(context)))
      end

      # `executeGlobalScriptElement`: each `<script>` child of `<scxml>` in
      # document order against the datamodel the one before it left. A
      # script that did not compile, or whose run fails, raises
      # `error.execution` (origin `{kind: :global_script, index:}`), keeping
      # what a failing run wrote. Each answers a
      # {Effect::Trace::ContentExecuted} naming no node.
      #
      # @return [Stepped]
      def run_global_scripts(state)
        state.machine.global_scripts.each_with_index.reduce(Stepped.new(state:, effects: [])) do |acc, (script, index)|
          acc.then_step(run_global_script(acc.state, script, { kind: :global_script, index: }))
        end
      end

      # One `<script>` child of `<scxml>`, as {run_global_scripts}.
      #
      # @return [Stepped]
      def run_global_script(state, script, origin)
        executed = Datamodel.execute(state.context, script)
        after = state.with(datamodel: Ractor.make_shareable(executed.data))
        after = after.raise_failure(origin, executed.error) unless executed.ok?
        Stepped.new(state: after, effects: Blocks.traced(after, Effect::Trace::ContentExecuted, owner: origin,
                                                                                                c_indexes: []))
      end

      # The root's `<initial>` transition, or the one the reference
      # synthesizes from the root's default targets; a synthesized
      # transition is no document element and has no index.
      def initial_transition(machine)
        root = machine.state(0)
        return machine.transitions.fetch(root.initial_transition) unless root.initial_transition.nil?

        Machine::Transition.new(t_index: nil, source: 0, targets: root.initial, events: [].freeze, cond: nil,
                                type: :external, content: [].freeze, location: machine.location, cond_location: nil,
                                attribute_locations: {}.freeze)
      end
    end
  end
end
