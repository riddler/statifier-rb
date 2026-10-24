# frozen_string_literal: true

module Statifier
  module Driver
    # One call's work in progress, a value threaded through the driver's
    # functions as the interpreter's loop threads its machine state: the
    # {State} as it stands, the `effects` answered so far, the call's
    # `processors` and `clock`, and the call's own budget counts: `counted`,
    # the external events an undelayed send queued for the session in this
    # call; `taken`, how many of those the call has taken; `sent_internal`,
    # the undelayed sends it delivered onto its own internal queue; and
    # `spent`, set once the call has halted the session for its budget; and
    # `outbox`, what an invoked child's run sent its parent, each a
    # `[Mail, counted]` pair, `counted` true for an undelayed send's event.
    # A run of an invoked child is a work of its own, its counts its own.
    #
    # @api private
    Work = ::Data.define(:state, :effects, :processors, :clock, :counted, :taken, :sent_internal, :spent,
                         :outbox) do
      # The interpreter's position.
      def machine_state = state.machine_state

      # The work with the interpreter's position replaced.
      def with_machine(machine_state) = with(state: state.with(machine_state:))

      # The work with the driver's own fields of the state replaced.
      def with_state(**fields) = with(state: state.with(**fields))

      # The round budget the chart was started with.
      def budget = machine_state.max_macrostep_rounds

      # Whether `count` is within the round budget.
      def within?(count) = budget == :infinity || count <= budget

      # The {Context} a processor is handed.
      def context = Context.new(session_id: state.session_id)

      # Whether `event` was queued by an undelayed send in this call.
      def counted?(event) = counted.any? { _1.equal?(event) }

      # What the call answers.
      def moved = Moved.new(state:, effects: effects.freeze)

      # The work with `effects` answered, in order.
      def report_all(effects) = with(effects: (self.effects + effects).freeze)

      # The work with `invocation` live under its id.
      def put_invocation(invocation)
        with_state(invocations: state.invocations.merge(invocation.invoke_id => invocation).freeze)
      end

      # The work with the invocation under `invoke_id` no longer live.
      def drop_invocation(invoke_id) = with_state(invocations: state.invocations.except(invoke_id).freeze)

      # A child's state on this session's clock and timer sequence.
      def synced(child) = child.with(now_ms: state.now_ms, timer_sequence: state.timer_sequence)

      # The work with the routes its session can reach declared to the core:
      # its own id, whether it has a parent and its live invocations.
      def stamped = with_machine(machine_state.with(sends: machine_state.sends.with(routes:)))

      # The {Interpreter::Targets::Routes} the session reaches now.
      def routes
        Calls.own_routes(state.session_id, parent: !state.invoked_as.nil?, invokes: state.invocations.keys.sort)
      end

      # Whether the session reaches `route` (a {Interpreter::Targets::Route})
      # now: its own `#_scxml_` address, its parent when it has one, and a
      # live invocation; the targets that need no route are always reached.
      def reaches?(route)
        case route.kind
        when :session then route.id == state.session_id
        when :parent then !state.invoked_as.nil?
        when :invoke then state.invocations.key?(route.id)
        else true
        end
      end

      # The work with `mail` sent to the parent.
      def post(mail, counted: false) = with(outbox: (outbox + [[mail, counted]]).freeze)

      # `effect` as the call reports it: an invoked child's wrapped in an
      # {Effect::Child} naming the child.
      def report(effect)
        state.invoked_as.nil? ? effect : Effect::Child.new(session_id: state.session_id, effect:)
      end
    end

    # How a call runs a chart: acting on the effects the core answers, in
    # order, and taking the external queue one event per macrostep.
    #
    # @api private
    module Run
      module_function

      # A call's work, before anything ran, over `state`.
      #
      # @return [Work]
      def begin_call(state, processors, clock)
        Work.new(state:, effects: [].freeze, processors:, clock:, counted: [].freeze, taken: 0, sent_internal: 0,
                 spent: false, outbox: [].freeze)
      end

      # Acts on a batch of effects in order. A delivery onto the internal
      # queue runs the chart at once, but its own effects are acted on after
      # the batch, as the reference defers them; each is answered as it is
      # acted on, so what a child it starts or reaches answers follows it. A
      # child whose batch stops it tells its parent first
      # ({Mailbox.announce}).
      #
      # @return [Work]
      def perform(work, effects)
        batch = effects
        until batch.empty?
          work = Mailbox.announce(work, batch)
          work, batch = batch.reduce([work, []]) do |(acc, deferred), effect|
            acc, more = perform_one(acc.with(effects: (acc.effects + [acc.report(effect)]).freeze), effect)
            [acc, deferred + more]
          end
        end
        work
      end

      # One effect acted on: `[work, deferred effects]`.
      def perform_one(work, effect)
        case effect
        when Effect::Send then Routing.send_now(work, effect)
        when Effect::SendDelayed then Routing.send_later(work, effect)
        when Effect::Cancel then [Routing.cancel(work, effect), []]
        when Effect::Done then [stopped(work, effect), []]
        when Effect::BudgetExhausted then [work.with_state(halted: :budget_exhausted), []]
        else Invocations.perform(work, effect)
        end
      end

      # The chart stopped: the {Effect::Done} is kept, and the pending timers,
      # the queued external events, the untaken mail and the invocations
      # its stop left (the completed ones) are discarded. A child that
      # stopped on its own sends its parent its donedata.
      def stopped(work, done)
        Mailbox.return_done(work.with_state(done:, timers: [].freeze, external_queue: [].freeze, mailbox: [].freeze,
                                            invocations: {}.freeze), done)
      end

      # Takes the external queue one event per macrostep, while the chart
      # runs and nothing has halted it, and, once it is empty, the mailbox
      # one entry at a time ({Mailbox.take_mail}). A counted entry the
      # session would take past its round budget in this call is left
      # queued, and the session halts.
      #
      # @return [Work]
      def drain(work)
        loop do
          entry, from = next_entry(work)
          return work if entry.nil?

          work = work.with(taken: work.taken + 1) if work.counted?(entry)
          return halt(work) unless work.within?(work.taken)

          work = take_entry(work, entry, from)
        end
      end

      # The entry the drain takes next and where it waits (`:external` or
      # `:mailbox`): none once the chart has stopped or a budget has halted
      # it.
      def next_entry(work)
        state = work.state
        return nil unless state.halted.nil? && work.machine_state.running
        return [state.external_queue.first, :external] unless state.external_queue.empty?

        [state.mailbox.first, :mailbox] unless state.mailbox.empty?
      end

      # One entry taken off where it waits.
      def take_entry(work, entry, from)
        state = work.state
        return take(work.with_state(external_queue: state.external_queue.drop(1).freeze), entry) if from == :external

        Mailbox.take_mail(work.with_state(mailbox: state.mailbox.drop(1).freeze), entry)
      end

      # One external event, one macrostep.
      def take(work, event)
        handled = Interpreter::Loop.handle_event(work.machine_state, event, clock: work.clock)
        return work unless handled.ok?

        perform(work.with_machine(handled.state), handled.effects)
      end

      # The session halted for this call's round budget, with the effect a
      # macrostep that spends its rounds answers.
      def halt(work) = perform(work.with(spent: true), Interpreter::Macrostep.exhausted(work.machine_state))
    end
  end
end
