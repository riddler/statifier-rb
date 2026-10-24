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
  # batch that sent it, as the reference defers them. A session the driver
  # runs has no parent and starts no invocation, so `#_parent`, `#_<id>`
  # and another session's address reach nothing: the core refuses such an
  # immediate send itself (the driver declares the routes it can reach when
  # the chart starts), and a delayed one fails when its timer fires, with
  # `error.communication` on the internal queue.
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
  # that processor's `cancel` once. What `deliver` answers is not read.
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
      :done, :send_types
    )

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
    #     they were made, a frozen list of {Statifier::Effect} values
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

    # The round budget when the host sets none.
    MAX_MACROSTEP_ROUNDS = Interpreter::MachineState::MAX_MACROSTEP_ROUNDS
  end
end

require_relative "driver/session_id"
require_relative "driver/work"
require_relative "driver/routing"
require_relative "driver/checks"
require_relative "driver/calls"
