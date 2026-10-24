# frozen_string_literal: true

module Statifier
  module Driver
    # The bodies of the driver's calls, which {Statifier.start},
    # {Statifier.step}, {Statifier.advance}, {Statifier.configuration} and
    # {Statifier.done?} answer through, and the checks on what a host
    # passes them.
    #
    # @api private
    module Calls
      module_function

      # {Statifier.start}'s body.
      #
      # @return [Result]
      def start(machine, options)
        options = Checks.start_options(options)
        types, session_id = options.values_at(:types, :session_id)
        started = Interpreter::Loop.initialize(machine, **options.slice(:session_id, :clock, :datamodel, :trace,
                                                                        :max_macrostep_rounds), **seams(options))
        work = Run.begin_call(fresh(started.state, session_id, types), options[:processors], options[:clock])
        ok(Run.drain(Run.perform(work, started.effects)).moved)
      end

      # What the driver declares to the interpreter as the chart starts: the
      # registered types, their `_ioprocessors` entries and the routes.
      def seams(options)
        types, session_id = options.values_at(:types, :session_id)
        { send_types: (types unless types.empty?), ioprocessors: entries(options[:processors], types, session_id),
          routes: own_routes(session_id) }
      end

      # The driver's state over a machine state that has just started.
      def fresh(machine_state, session_id, types)
        State.new(machine_state:, session_id:, now_ms: 0, timers: [].freeze, timer_sequence: 0,
                  external_queue: [].freeze, held_sends: {}.freeze, halted: nil, done: nil, send_types: types,
                  invocations: {}.freeze, mailbox: [].freeze, invoked_as: nil, cancelled: false)
      end

      # {Statifier.step}'s body.
      #
      # @return [Result]
      def step(state, name, data:, processors:, clock:)
        work = Run.begin_call(Checks.state(state, processors), processors, clock)
        raise TypeError, "an event name is a String, got #{name.class}" unless name.is_a?(String)
        return refused(:not_running) unless state.machine_state.running

        ok(Run.drain(Routing.enqueue(work, Event.external(name, data:), counted: false).stamped).moved)
      end

      # {Statifier.advance}'s body: the clock moved `milliseconds` forward, every
      # timer due by then, anywhere in the tree of sessions, fired in
      # due-then-scheduled order, each run to completion before the next: the
      # session it fired in, then each session above it.
      #
      # @return [Result]
      def advance(state, milliseconds, processors:, clock:)
        work = Run.begin_call(Checks.state(state, processors), processors, clock)
        return refused(:invalid_duration) unless duration?(milliseconds)

        until_ms = state.now_ms + milliseconds
        while (found = next_due(work.state, until_ms))
          path, timer = found
          work = fire_at(work.with_state(now_ms: timer.due_ms), path, timer)
        end
        ok(work.with_state(now_ms: until_ms).moved)
      end

      # The timer fired in the session `path` (the invoke ids from this
      # session down) names, each session on the way drained after it.
      def fire_at(work, path, timer)
        return fire(due(work, timer), timer.delayed) if path.empty?

        Run.drain(Mailbox.within(work, path.first) { fire_at(_1, path.drop(1), timer) })
      end

      # Whether `value` is a duration the clock can move by: a real number,
      # finite and not negative.
      def duration?(value) = value.is_a?(Numeric) && value.real? && value.finite? && value >= 0

      # The work with `timer` taken off the pending timers and the clock at
      # its due time.
      def due(work, timer)
        work.with_state(timers: work.state.timers.reject { _1.equal?(timer) }.freeze, now_ms: timer.due_ms)
      end

      # The earliest pending timer due by `until_ms` in the tree, the first
      # scheduled among equals, as `[path, timer]`, or nil.
      def next_due(state, until_ms)
        pending(state, []).select { _2.due_ms <= until_ms }.min_by { [_2.due_ms, _2.sequence] }
      end

      # Every pending timer of the tree under `state`, each with the path to
      # its session.
      def pending(state, path)
        state.timers.map { [path, _1] } +
          state.invocations.flat_map { |id, invocation| pending(invocation.child, path + [id]) }
      end

      # A fired timer's send, routed as an immediate one is but never
      # counted, then the external queue taken. While a macrostep's budget
      # has halted the session, a send to the session itself still joins
      # its external queue, and any other is dropped, as the reference drops
      # it.
      def fire(work, send)
        unless work.state.halted.nil?
          return work unless Routing.destination(work, send) == :external

          return Routing.enqueue(work, Routing.delivered_event(send, work.state.session_id), counted: false)
        end

        work, deferred = Routing.route(work.stamped, send, undelayed: false)
        Run.drain(Run.perform(work, deferred))
      end

      # {Statifier.configuration}'s body: the active states' ids, the root
      # left out, sorted. A state the document gave no id is named `#` and
      # its index, a spelling no XML id can take.
      #
      # @return [Result]
      def configuration(state)
        Checks.state(state, nil)
        ok(names(state.machine_state.machine, state.machine_state.configuration - [0]))
      end

      # {Statifier.done?}'s body.
      #
      # @return [Result]
      def done?(state)
        Checks.state(state, nil)
        done = state.done
        return ok(DoneStatus.new(done: false, donedata: nil, configuration: nil)) if done.nil?

        ok(DoneStatus.new(done: true, donedata: done.donedata,
                          configuration: names(state.machine_state.machine, done.configuration - [0])))
      end

      # The states at `indexes` by name, sorted, a frozen list.
      def names(machine, indexes) = indexes.map { machine.state(_1).id || "##{_1}" }.sort.freeze

      # A successful result.
      def ok(value) = Result.new(value:, error: nil)

      # A refused call.
      def refused(reason) = Result.new(value: nil, error: reason)

      # The routes a session the driver runs can reach: itself, its parent
      # when it has one, and its live invocations, by id.
      def own_routes(session_id, parent: false, invokes: [].freeze)
        Interpreter::Targets::Routes.new(sessions: [session_id].freeze, parent?: parent, invokes: invokes.freeze)
      end

      # Each registered type's `_ioprocessors` entry, asked of its processor
      # once as the chart starts; empty when it answers none.
      def entries(processors, types, session_id)
        context = Context.new(session_id:)
        types.to_h do |type|
          processor = processors[type]
          [type, processor.respond_to?(:ioprocessors_entry) ? processor.ioprocessors_entry(type, context) : {}]
        end
      end
    end
  end
end
