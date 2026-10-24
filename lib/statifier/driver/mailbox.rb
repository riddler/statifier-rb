# frozen_string_literal: true

module Statifier
  module Driver
    # What passes between a session and its invoked children, as the
    # reference's session passes it (`Statifier.Session`, its
    # `Statifier.Session.Invocations` table and `Statifier.Invoke.Answer` in
    # statifier-ex): a child run inside its parent's work ({within}), an
    # event delivered to a child, and what a child sends its parent - an
    # event to `#_parent`, the notice that it completed and its donedata -
    # waiting in the parent's mailbox until the parent takes it.
    #
    # @api private
    module Mailbox
      module_function

      # The child under `invoke_id` run by the block, which takes and
      # answers the child's work, then its state, timer sequence, effects
      # and mail taken back.
      #
      # @return [Work]
      def within(work, invoke_id)
        invocation = work.state.invocations.fetch(invoke_id)
        ran = yield Run.begin_call(work.synced(invocation.child), work.processors, work.clock)
        receive(absorb(work.put_invocation(invocation.with(child: ran.state)), ran), ran.outbox)
      end

      # The work with what a child's run left it: the timer sequence and the
      # effects.
      def absorb(work, ran) = work.with_state(timer_sequence: ran.state.timer_sequence).report_all(ran.effects)

      # The work with a child's mail in its mailbox, an undelayed send's
      # counted.
      def receive(work, outbox)
        outbox.reduce(work) do |acc, (mail, counted)|
          acc = acc.with_state(mailbox: (acc.state.mailbox + [mail]).freeze)
          counted ? acc.with(counted: (acc.counted + [mail]).freeze) : acc
        end
      end

      # A send to `#_parent`: the event, stamped with the invoke id, into
      # the parent's mailbox.
      def to_parent(work, event, counted:)
        event = Effect.frozen_copy(event.with(invokeid: work.state.invoked_as))
        work.post(Mail.new(kind: :event, invoke_id: work.state.invoked_as, payload: event), counted:)
      end

      # An event for the live child under `invoke_id`: it joins the child's
      # external queue and the child runs to a stable configuration. Nothing
      # reaches an invocation that is not live, or a child that has stopped.
      def deliver(work, invoke_id, event)
        invocation = work.state.invocations[invoke_id]
        return work if invocation.nil? || !invocation.child.machine_state.running

        within(work, invoke_id) { Run.drain(Routing.enqueue(_1, event, counted: false).stamped) }
      end

      # A child whose batch stops it tells its parent it completed, ahead of
      # everything the batch sends; a cancelled child does not.
      #
      # @return [Work]
      def announce(work, batch)
        state = work.state
        return work if state.invoked_as.nil? || state.cancelled || batch.none?(Effect::Done)

        work.post(Mail.new(kind: :completed, invoke_id: state.invoked_as, payload: nil))
      end

      # A child that stopped on its own sends its parent its donedata; one
      # that was cancelled sends nothing.
      #
      # @return [Work]
      def return_done(work, done)
        state = work.state
        return work if state.invoked_as.nil? || state.cancelled

        work.post(Mail.new(kind: :done, invoke_id: state.invoked_as, payload: done.donedata))
      end

      # One mailbox entry. One that carries an event declares the routes as
      # it arrives; an entry whose invocation is no longer live is
      # discarded.
      #
      # @return [Work]
      def take_mail(work, mail)
        work = work.stamped unless mail.kind == :completed
        invocation = work.state.invocations[mail.invoke_id]
        invocation.nil? ? work : open_mail(work, mail, invocation)
      end

      # A live invocation's entry: a completion notice marks it completed;
      # an event is taken as an external event; and the done event, built
      # here, retires it once taken.
      #
      # @return [Work]
      def open_mail(work, mail, invocation)
        case mail.kind
        when :completed then work.put_invocation(invocation.with(completed: true))
        when :event then Run.take(work, mail.payload)
        else Run.take(work, done_event(work.state.session_id, invocation, mail.payload)).drop_invocation(mail.invoke_id)
        end
      end

      # The reference's `Invoke.Answer.done/4`: `done.invoke.` and the
      # invoke id, its data the child's donedata, from the parent's own
      # address, carrying the invocation's `caller_context`.
      #
      # @return [Event]
      def done_event(session_id, invocation, donedata)
        Effect.frozen_copy(Event.external(
                             "done.invoke.#{invocation.invoke_id}",
                             data: donedata, invokeid: invocation.invoke_id,
                             origin: Datamodel::SystemVariables.scxml_location(session_id),
                             origintype: Datamodel::SystemVariables::SCXML_EVENT_PROCESSOR,
                             caller_context: invocation.caller_context
                           ))
      end
    end
  end
end
