# frozen_string_literal: true

module Statifier
  module Interpreter
    # The interpreter's position, as the reference keeps it
    # (`Statifier.MachineState` in statifier-ex): every global and loop
    # variable of the specification's pseudocode as one immutable value, so
    # a position between two calls is data and never a stack frame. Every
    # function of the loop takes one and answers the one it leaves.
    #
    # The fields: `machine`; `configuration`, the active state indexes, a
    # frozen ascending Array; `history`, the recorded value of each history
    # state that has one; `datamodel`; `internal_queue`, the queued
    # {Event}s, oldest first; `entered_states`, every state ever entered
    # (a state's own `<data>` binds on its first entry under late binding);
    # `states_to_invoke`, the states entered since the last invoke pass;
    # `sends`, the {Send::SendState}; `caller_context`, the opaque value the
    # host attached to the event the current macrostep handles, nil for
    # none; `clock`, the host's clock for the current call, nil for
    # predicator's own; `last_selection`, `:selected` or `:none` for the
    # last external event, nil before one; `running`, false once a
    # top-level final is entered; `status`, `:running`, or `:done` once the
    # chart has stopped; the counters `macrostep`, `microstep` and `round`;
    # `trace`, whether the loop answers trace effects;
    # `max_macrostep_rounds`, the round budget, a positive Integer or
    # `:infinity`; `active_invocations`, the live invocations, a frozen Hash
    # of `[state_index, invoke_index]` to the invocation's id; and
    # `invoke_counter`, the sequence a generated invoke id is minted from.
    # The invoke pass ({Invoke.invoke_pass}) records an invocation of the
    # built-in type there, and the cancel of its state removes it.
    #
    # The counters: `macrostep` advances once when the chart starts and once
    # per external event, and starts the other two over; `microstep`
    # advances once per microstep that exits and enters (the initial entry is
    # microstep 1); `round` once per pass of the macrostep's loop, a pass
    # that moves nothing included.
    #
    # @api private
    MachineState = ::Data.define(
      :machine, :configuration, :history, :datamodel, :internal_queue, :entered_states, :states_to_invoke,
      :sends, :caller_context, :clock, :last_selection, :running, :status, :macrostep, :microstep, :round,
      :trace, :max_macrostep_rounds, :active_invocations, :invoke_counter
    ) do
      # The {Snapshot} selection, exit and entry read.
      def snapshot = Snapshot.new(machine:, configuration:, history:)

      # The {Datamodel::Context} an evaluation site runs against now.
      def context = Datamodel.context(datamodel, machine, configuration, clock:)

      # The counters as they stand.
      def counters = { macrostep:, microstep:, round: }

      # The {Event::Cause} of an event raised now about `origin`.
      def cause(origin) = Event::Cause.new(origin:, **counters)

      # A new macrostep: the other two counters start over.
      def begin_macrostep = with(macrostep: macrostep + 1, microstep: 0, round: 0)

      # The next microstep.
      def begin_microstep = with(microstep: microstep + 1)

      # The next round.
      def begin_round = with(round: round + 1)

      # The state with `events` queued, in order.
      def enqueue(*events) = with(internal_queue: (internal_queue + events).freeze)

      # The state with a platform event named `name` queued, its cause
      # `origin` and the counters as they stand.
      def raise_platform(name, origin, data: Predicator::UNDEFINED, sendid: nil)
        enqueue(Effect.frozen_copy(Event.platform(name, cause(origin), data:, sendid:)))
      end

      # The state with an `error.execution` queued about `origin`, its data
      # the failure `reason` as a predicator value
      # ({Datamodel::ReasonValue.of}).
      def raise_failure(origin, reason)
        raise_platform("error.execution", origin, data: Datamodel::ReasonValue.of(reason))
      end

      # The state with an internal event queued, as {raise_platform}.
      def raise_internal(name, origin, data: Predicator::UNDEFINED, sendid: nil)
        enqueue(Effect.frozen_copy(Event.internal(name, cause(origin), data:, sendid:)))
      end

      # The oldest queued event and the state without it, or nil when the
      # queue is empty.
      def dequeue
        return nil if internal_queue.empty?

        [internal_queue.first, with(internal_queue: internal_queue.drop(1).freeze)]
      end

      # The state with `_event` set to `event`'s value.
      def put_event(event)
        with(datamodel: Ractor.make_shareable(Datamodel::SystemVariables.put_event(datamodel, event.system_value)))
      end

      # Whether the state at `index` is active.
      def active?(index) = configuration.include?(index)
    end

    # The constructor of a fresh position and its defaults.
    class MachineState
      # The round budget when the host sets none.
      MAX_MACROSTEP_ROUNDS = 10_000

      # The options {fresh} takes, as they stand when the host names none.
      OPTIONS = {
        datamodel: {}.freeze, send_types: nil, ioprocessors: {}.freeze, routes: nil, trace: false,
        max_macrostep_rounds: MAX_MACROSTEP_ROUNDS
      }.freeze

      # Every field of a position before anything is entered.
      EMPTY = {
        configuration: [].freeze, history: {}.freeze, internal_queue: [].freeze, entered_states: [].freeze,
        states_to_invoke: [].freeze, caller_context: nil, clock: nil, last_selection: nil, running: true,
        status: :running, macrostep: 0, microstep: 0, round: 0, active_invocations: {}.freeze, invoke_counter: 0
      }.freeze

      # A fresh position over `machine`: nothing entered, the counters at
      # zero, and the host's `datamodel` with the system variables over it
      # (`session_id`, the id the host minted; `send_types`, the types it
      # registered a processor for, or nil for none; `ioprocessors`, the
      # `_ioprocessors` entry of each, by type). `routes` are the
      # {Targets::Routes} the driver declares, or nil; `trace` and
      # `max_macrostep_rounds` as the fields. The datamodel is copied before
      # it is frozen, so nothing the host passed is frozen in place.
      #
      # @return [MachineState]
      # @raise [ArgumentError] for an option {OPTIONS} does not name
      def self.fresh(machine, session_id:, **options)
        unknown = options.keys - OPTIONS.keys
        raise ArgumentError, "unknown options: #{unknown.inspect}" unless unknown.empty?

        options = OPTIONS.merge(options)
        sends = Send::SendState::INITIAL.with(send_types: options[:send_types]&.dup&.freeze, routes: options[:routes])
        new(machine:, **EMPTY, datamodel: seeded(machine, session_id, options), sends:,
            **options.slice(:trace, :max_macrostep_rounds))
      end

      # The starting datamodel, a deeply frozen copy.
      def self.seeded(machine, session_id, options)
        seeded = Datamodel::SystemVariables.seed(options[:datamodel], session_id:, name: machine.name,
                                                                      entries: options[:ioprocessors])
        Ractor.make_shareable(seeded, copy: true)
      end
      private_class_method :seeded
    end
  end
end
