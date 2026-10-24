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
    # `spent`, set once the call has halted the session for its budget.
    #
    # @api private
    Work = ::Data.define(:state, :effects, :processors, :clock, :counted, :taken, :sent_internal, :spent) do
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
                 spent: false)
      end

      # Acts on a batch of effects in order. A delivery onto the internal
      # queue runs the chart at once, but its own effects are acted on after
      # the batch, as the reference defers them; each is answered in the
      # order acted on.
      #
      # @return [Work]
      def perform(work, effects)
        batch = effects
        until batch.empty?
          work = work.with(effects: (work.effects + batch).freeze)
          work, batch = batch.reduce([work, []]) do |(acc, deferred), effect|
            acc, more = perform_one(acc, effect)
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
        else [work, []]
        end
      end

      # The chart stopped: the {Effect::Done} is kept, and the pending timers
      # and queued external events are discarded.
      def stopped(work, done) = work.with_state(done:, timers: [].freeze, external_queue: [].freeze)

      # Takes the external queue one event per macrostep, while the chart
      # runs and nothing has halted it. A counted event the session would
      # take past its round budget in this call is left queued, and the
      # session halts.
      #
      # @return [Work]
      def drain(work)
        loop do
          event = next_event(work)
          return work if event.nil?

          work = work.with(taken: work.taken + 1) if work.counted?(event)
          return halt(work) unless work.within?(work.taken)

          work = take(work.with_state(external_queue: work.state.external_queue.drop(1).freeze), event)
        end
      end

      # The external event the drain takes next: none once the chart has
      # stopped or a budget has halted it.
      def next_event(work)
        return nil unless work.state.halted.nil? && work.machine_state.running

        work.state.external_queue.first
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
