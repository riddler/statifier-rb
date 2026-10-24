# frozen_string_literal: true

require_relative "interpreter"

module Statifier
  # The in-memory driver: the small loop around the interpreter that a host
  # steps a chart with, as the reference's session is (`Statifier.Session`
  # and `Statifier.Session.Effects` in statifier-ex), with no process, no
  # real clock and no I/O. {Statifier.start}, {Statifier.step} and
  # {Statifier.advance} are its calls; this module holds what they answer
  # and the work behind them.
  #
  # The driver keeps the external queue and the delayed sends as pending
  # timers on a virtual clock, routes every `<send>` the core answers, and
  # hands a send of a registered type to the host's processor for that
  # type. Every call takes a {State} and answers a new one, never changing
  # the one it was given; nothing is kept between calls but what the
  # answered state holds.
  #
  # Routing, as the reference's planner and session route a send. A send
  # with no target, or to this session's own `#_scxml_` address, joins the
  # external queue. A send to `#_internal` is delivered onto the internal
  # queue through the interpreter's internal delivery
  # ({Interpreter::Loop.deliver_internal}), and the chart runs to a stable
  # configuration again; the effects of that run are acted on after the
  # batch that sent it, as the reference defers them. `#_parent` from an
  # invoked child, and `#_<invokeid>` naming a live invocation, deliver as
  # external events (below). Another session's address, a parent a session
  # does not have and an invocation that is not live reach nothing: the core
  # refuses such an immediate send itself (the driver declares the routes a
  # session can reach, its own id, whether it has a parent and the ids of
  # its live invocations, when it starts, when an event reaches it from
  # outside, when a timer fires in it and before an internal delivery), a
  # send the declaration reaches that names nothing live by the time it is
  # routed fails here, and a delayed one is judged when its timer fires,
  # each with `error.communication` on the internal queue.
  #
  # Invocations, as the reference's session and its built-in `scxml`
  # handler run them (`Statifier.Session`, `Statifier.Session.Invocations`
  # and `Statifier.Invoke.Source` in statifier-ex), with one tree of
  # session states in place of processes. An {Effect::Invoke} of the SCXML
  # type whose content is markup compiles it, with the namespace relaxed as
  # inline content is placed, and starts it as a child session, its session
  # id its parent's, a dot and the invoke id, its datamodel seeded with the
  # params a root `<data>` of the child names, the rest dropped. A content
  # that is not markup, or does not compile, and an invocation with no
  # content (`src` is never fetched) raise `error.communication` and record
  # nothing; any other type raises `error.execution`. A child is stepped by
  # this driver on its parent's virtual clock: starting it, an event sent to
  # it and an autoforwarded event each run it to a stable configuration at
  # once, and its timers fire with its parent's, in due-then-scheduled order
  # across the tree. A child inherits its parent's registered send types
  # (its processors are the call's, handed the child's own session id) and
  # its trace flag, and every effect its runs answer is among the call's
  # effects, in the order made, as an {Effect::Child} naming its session id.
  #
  # What a child sends its parent - an event to `#_parent`, stamped with the
  # invoke id; a notice that it reached a top-level final, ahead of the
  # batch that stops it; and its `done.invoke.<id>` with its donedata -
  # waits in the parent's mailbox, taken one entry at a time once the
  # parent's external queue is empty. An entry whose invocation is no longer
  # live is discarded; the done event retires its invocation once taken. An
  # {Effect::CancelInvoke} retires the invocation and stops its child,
  # running its `<onexit>` handlers, unless the child already said it
  # completed; a cancelled child returns no done event. An
  # {Effect::Autoforward} delivers the event, unchanged, to a live child.
  #
  # The virtual clock. A delayed send of a built-in type becomes a pending
  # timer due at the clock's time plus its delay. {Statifier.advance} moves
  # the clock forward and fires every timer due by the new time, earliest
  # first and, at one due time, in the order they were scheduled; each
  # fired send is routed then, and a self-addressed one is taken as an
  # external event before the next timer fires. A `<cancel>` removes every
  # pending timer under its send id. When the chart stops, its pending
  # timers and its queued external events are discarded.
  #
  # Registered send types. The processors a host registers are passed with
  # every call, by type, and name the same types for the whole life of a
  # chart: the types are fixed when the chart starts, as the reference fixes
  # `_ioprocessors` then. A send of a registered type is handed to its
  # processor's `deliver` with the event a delivery would carry and a
  # {Context}, and is never routed or scheduled, delayed or not: the
  # processor holds a delayed one, and a `<cancel>` of its send id reaches
  # that processor's `cancel` once. What `deliver` answers is not read,
  # unless it is a {DeliveryFailure}.
  #
  # A failed send. A send a processor could not deliver comes back to the
  # chart as `error.communication` on its internal queue, its origin the
  # send's content and its `sendid` the send's id whether or not its author
  # named it, as the reference's `Statifier.Session.failed_send/3` writes it.
  # A failure the processor knows of while it is handed the send is answered
  # from `deliver` as a {DeliveryFailure}, and the event is raised then, at
  # the send's place in the call, as the reference raises the failure its
  # processor plans in `deliver/3`. A failure the host learns of later is
  # reported through {Statifier.report_send_failed}, with the send it was
  # handed: the driver keeps no table of handed sends. The reason the host
  # gives is not read, and the chart is not handed it.
  #
  # A macrostep that spends its round budget halts the driver as the
  # reference halts its session: further external events are queued and not
  # taken, and pending timers still fire. One call also spends that budget
  # twice more, so that it always returns where the reference's session
  # would keep running: against the events it takes that an undelayed send
  # queued for the session in this call, and against the undelayed sends it
  # delivers onto its own internal queue. A fired timer's event is never
  # counted, and an `:infinity` budget bounds neither.
  module Driver
    # A chart's execution between two calls: an immutable value a host keeps
    # and hands back, reading it only through {Statifier.configuration} and
    # {Statifier.done?}. Its members are internal and may change in any
    # release.
    #
    # @api private
    State = ::Data.define(
      :machine_state, :session_id, :now_ms, :timers, :timer_sequence, :external_queue, :held_sends, :halted,
      :done, :send_types, :invocations, :mailbox, :invoked_as, :cancelled
    )

    # A live invocation of a child session, as the parent holds it: its
    # `invoke_id`; `autoforward`; `completed`, set once the child said it
    # reached a top-level final; `caller_context`, the {Effect::Invoke}'s,
    # which its done event carries; and `child`, the child's {State}, whose
    # `now_ms` and `timer_sequence` are its parent's as they stood when the
    # child last ran.
    #
    # @api private
    Invocation = ::Data.define(:invoke_id, :autoforward, :completed, :caller_context, :child)

    # What a child sent its parent and the parent has not taken: `kind`
    # `:completed` (no `payload`), `:event` (the {Event}) or `:done` (the
    # child's donedata), and the `invoke_id` it came from.
    #
    # @api private
    Mail = ::Data.define(:kind, :invoke_id, :payload)

    # A delayed send waiting on the virtual clock: its send id, the virtual
    # time it is due at, the order it was scheduled in, and the
    # {Effect::SendDelayed} itself, `delayed`.
    #
    # @api private
    Timer = ::Data.define(:send_id, :due_ms, :sequence, :delayed)

    # What a call that moves a chart answers as its result's `value`.
    #
    # @!attribute [r] state
    #   @return [State] the chart's execution after the call
    # @!attribute [r] effects
    #   @return [Array] every effect the call's runs answered, in the order
    #     they were made, a frozen list of {Statifier::Effect} values, an
    #     invoked child's each wrapped in an {Effect::Child}
    Moved = ::Data.define(:state, :effects)

    # What {Statifier.done?} answers as its result's `value`.
    #
    # @!attribute [r] done
    #   @return [Boolean] whether the chart has stopped
    # @!attribute [r] donedata
    #   @return [Object, nil] the top-level final's `<donedata>` as the
    #     {Effect::Done} carried it (`Predicator::UNDEFINED` when it has
    #     none); nil while the chart runs
    # @!attribute [r] configuration
    #   @return [Array<String>, nil] the states active when the chart
    #     stopped, named as {Statifier.configuration} names them; nil while
    #     the chart runs
    DoneStatus = ::Data.define(:done, :donedata, :configuration) do
      # @return [Boolean] whether the chart has stopped
      def done? = done
    end

    # What the driver tells a processor about the session it is called
    # for.
    #
    # @!attribute [r] session_id
    #   @return [String] the session's id, the one `_sessionid` reads
    Context = ::Data.define(:session_id)

    # What a processor's `deliver` answers for a send it could not deliver:
    # the send then fails within the call that handed it, as
    # {Statifier.report_send_failed} fails a send reported later.
    #
    # @!attribute [r] reason
    #   @return [Object, nil] the host's own account of the failure; the
    #     driver does not read it and the chart is not handed it
    DeliveryFailure = ::Data.define(:reason) do
      # A failure with no reason given.
      def initialize(reason: nil) = super
    end

    # The round budget when the host sets none.
    MAX_MACROSTEP_ROUNDS = Interpreter::MachineState::MAX_MACROSTEP_ROUNDS
  end
end

require_relative "driver/session_id"
require_relative "driver/work"
require_relative "driver/routing"
require_relative "driver/delivery"
require_relative "driver/checks"
require_relative "driver/invocations"
require_relative "driver/mailbox"
require_relative "driver/calls"
