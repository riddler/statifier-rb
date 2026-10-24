# frozen_string_literal: true

module Statifier
  module Driver
    # Where each `<send>` the core answers goes, as the reference's planner
    # (`Statifier.Session.Effects`) and its session's `deliver/5` route it:
    # to a host's processor ({Delivery}), onto the external queue, onto the
    # internal queue through the interpreter's internal delivery, onto a
    # pending timer, or nowhere, with `error.communication`. Each function answers
    # `[work, deferred effects]`, or the work alone where nothing is
    # deferred.
    #
    # @api private
    module Routing
      module_function

      # An immediate send: handed to its processor, or routed now.
      def send_now(work, send)
        return Delivery.hand_off(work, send) if registered?(work, send)

        route(work, send, undelayed: true)
      end

      # A delayed send: handed to its processor, which holds it, or a
      # pending timer due its delay from now.
      def send_later(work, send)
        return Delivery.hand_off(work, send) if registered?(work, send)

        [schedule(work, send), []]
      end

      # The work with a pending timer for the delayed send.
      def schedule(work, send)
        state = work.state
        timer = Timer.new(send_id: send.send_id, due_ms: state.now_ms + send.delay_ms, sequence: state.timer_sequence,
                          delayed: send)
        work.with_state(timers: (state.timers + [timer]).freeze, timer_sequence: timer.sequence + 1)
      end

      # Whether the send's type is one the host registered.
      def registered?(work, send)
        Interpreter::Targets.classify(work.machine_state.sends.send_types, send.type) == :registered
      end

      # A `<cancel>`: every pending timer under its id goes, and each
      # processor holding a delayed send under it is told once.
      #
      # @return [Work]
      def cancel(work, cancel)
        id = cancel.send_id
        work = work.with_state(timers: work.state.timers.reject { _1.send_id == id }.freeze)
        held = work.state.held_sends.fetch(id, nil)
        return work if held.nil?

        held.each { tell_cancel(work, _1, cancel) }
        release(work, id)
      end

      # The work with no processor holding a delayed send under `id`.
      def release(work, id) = work.with_state(held_sends: work.state.held_sends.except(id).freeze)

      # The processor for `type` told of the `<cancel>`, when it takes one.
      def tell_cancel(work, type, cancel)
        processor = work.processors.fetch(type)
        processor.cancel(cancel, work.context) if processor.respond_to?(:cancel)
      end

      # A built-in send routed: to the session itself (no target, or its own
      # `#_scxml_` address) onto the external queue, counted when the send
      # was undelayed; to `#_internal` onto the internal queue; to
      # `#_parent` into the parent's mailbox, counted there when undelayed;
      # to `#_<invokeid>` onto that live child's external queue; anything
      # else reaches nothing.
      def route(work, send, undelayed:)
        event = -> { delivered_event(send, work.state.session_id) }
        case destination(work, send)
        when :external then [enqueue(work, event.call, counted: undelayed), []]
        when :internal then internal(work, send, undelayed)
        when :parent then [Mailbox.to_parent(work, event.call, counted: undelayed), []]
        when :invoke then [Mailbox.deliver(work, Interpreter::Targets.parse_target(send.target).id, event.call), []]
        else communication_error(work, send)
        end
      end

      # Where a built-in send's target leads: `:external`, `:internal`,
      # `:parent` (a session that has one), `:invoke` (a live invocation) or
      # `:nowhere`.
      def destination(work, send)
        route = Interpreter::Targets.parse_target(send.target)
        work.reaches?(route) ? DESTINATIONS.fetch(route.kind, :nowhere) : :nowhere
      end

      # Where each kind of target leads when the session reaches it.
      DESTINATIONS = { self: :external, session: :external, internal: :internal, parent: :parent,
                       invoke: :invoke }.freeze

      # `event` joined to the external queue, marked as queued by an
      # undelayed send when `counted`.
      #
      # @return [Work]
      def enqueue(work, event, counted:)
        event = Effect.frozen_copy(event)
        work = work.with_state(external_queue: (work.state.external_queue + [event]).freeze)
        counted ? work.with(counted: (work.counted + [event]).freeze) : work
      end

      # A send to `#_internal`. An undelayed one is counted against this
      # call's budget; past it, the event waits on the internal queue unrun
      # and the session halts.
      def internal(work, send, undelayed)
        deliver = ->(acc) { deliver_internal(acc, :internal, name(send), origin(send), fields(send, send.data)) }
        undelayed ? counted(work, &deliver) : deliver.call(work)
      end

      # A delivery onto the internal queue counted against this call's
      # budget with the undelayed sends made there: made by `deliver` within
      # the budget, and past it made with the chart not run and the session
      # halted.
      def counted(work, &deliver)
        work = work.with(sent_internal: work.sent_internal + 1)
        work.within?(work.sent_internal) ? deliver.call(work) : past_budget(work, deliver)
      end

      # An internal delivery past this call's budget: made with the chart
      # not run, and the session halted, with the budget's effect when it
      # was not halted already.
      def past_budget(work, deliver)
        return [work, []] unless work.machine_state.running

        halted = !work.state.halted.nil?
        work, = deliver.call(work.with(spent: true))
        return [work, []] if halted

        [work.with_state(halted: :budget_exhausted), Interpreter::Macrostep.exhausted(work.machine_state)]
      end

      # A send to something the driver cannot reach: `error.communication`
      # on the internal queue, carrying the send id the delivered event
      # would have.
      def communication_error(work, send, sendid: author_id(send))
        deliver_internal(work, :platform, "error.communication", origin(send), { data: Predicator::UNDEFINED, sendid: })
      end

      # The interpreter's internal delivery: the event joins the internal
      # queue and the chart runs to a stable configuration, its effects
      # deferred. A stopped chart takes nothing; once the call has halted
      # the session for its budget, the event waits there unrun.
      # `fields` are the event's `data:` and `sendid:`.
      def deliver_internal(work, kind, name, origin, fields)
        state = work.machine_state
        return [work, []] unless state.running
        return [work.with_machine(queued(state, kind, name, origin, fields)), []] if work.spent

        handled = Interpreter::Loop.deliver_internal(work.stamped.machine_state, kind, name, origin, **fields,
                                                     clock: work.clock)
        [work.with_machine(handled.state), handled.effects]
      end

      # The machine state with the event queued and not run.
      def queued(state, kind, name, origin, fields)
        state.public_send(kind == :internal ? :raise_internal : :raise_platform, name, origin, **fields)
      end

      # An event's `data:` and `sendid:` about the send: `data`, and the
      # send's id when its author named it.
      def fields(send, data) = { data:, sendid: author_id(send) }

      # The event a delivered send carries, as the reference's
      # `Statifier.Send.Event.build/3` makes it: from this session's own
      # address through the SCXML Event I/O Processor, its send id only when
      # the author named one, and a delayed send's `caller_context`.
      #
      # @return [Event]
      def delivered_event(send, session_id)
        Event.external(name(send), data: send.data,
                                   origin: Datamodel::SystemVariables.scxml_location(session_id),
                                   origintype: Datamodel::SystemVariables::SCXML_EVENT_PROCESSOR,
                                   sendid: author_id(send),
                                   caller_context: send.is_a?(Effect::SendDelayed) ? send.caller_context : nil)
      end

      # The send's event name: the empty name for a send whose event is not
      # text.
      def name(send) = send.event.is_a?(String) ? send.event : ""

      # The send's id when its author named it, else nil.
      def author_id(send) = send.id_from_author? ? send.send_id : nil

      # The cause of an event about the send: its content node.
      def origin(send) = { kind: :content, c_index: send.c_index, owner: send.owner }
    end
  end
end
