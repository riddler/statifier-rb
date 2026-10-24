# frozen_string_literal: true

module Statifier
  # The effects executable content answers, ported field for field from the
  # reference's effect vocabulary (`Statifier.Effect.*` in statifier-ex):
  # plain data values a host reads, each a `Data` the block runner answers
  # as a deeply frozen copy, the values it carries included, except the
  # host's own `caller_context`, which it carries untouched. The reference tags
  # every effect with an atom beside its struct; here the class is the tag.
  #
  # Every effect carries the counters as they stood when it was made
  # (`macrostep`, `microstep`, `round`), and every effect content makes
  # carries the content node's `c_index` and its `owner`, the block it ran
  # in: `{kind: :onentry, state_index:, ordinal:}`,
  # `{kind: :onexit, state_index:, ordinal:}`, `{kind: :transition,
  # t_index:}` or `{kind: :finalize, state_index:, invoke_index:}`.
  #
  # A value is a predicator value: `nil` is null and `Predicator::UNDEFINED`
  # is no value at all.
  #
  # These are the effects the driver's calls answer a host
  # ({Driver::Moved}'s `effects`), and what a host's processor is handed.
  # Beside content's effects are the ones the interpreter's loop answers:
  # {DatamodelInit}, {BudgetExhausted}, {Done}, the invocation effects
  # ({Invoke}, {CancelInvoke} and {Autoforward}) and the {Trace} effects.
  # The driver adds one of its own, {Child}, which carries an effect an
  # invoked child's run answered.
  #
  # Every effect a call's runs answered is among the call's effects, in the
  # order made, whatever the driver did with it:
  #
  # - A {Send} or a {SendDelayed}, by its type. A type the host registered
  #   is handed to that type's processor (`deliver`), delayed or not. The
  #   SCXML type, or none, is routed by its target, and a {SendDelayed} of it
  #   waits as a pending timer until {Statifier.advance} reaches it. A send
  #   of any other type is refused inside the chart with `error.execution`
  #   and answers no effect.
  # - A {Cancel} drops every pending timer under its send id and tells a
  #   processor holding a delayed send under it, once.
  # - An {Invoke} of the SCXML type whose content is markup starts a child
  #   session in process (no content, or content that is not markup or does
  #   not compile, raises `error.communication`); any other type raises
  #   `error.execution` inside the chart. A {CancelInvoke} stops the child,
  #   and an {Autoforward} hands it the event.
  # - A {Log} is the host's to record; the driver does nothing with it.
  # - A {Done} says the chart stopped; its pending timers and queued external
  #   events are discarded.
  # - An error is never an effect: `error.execution` and
  #   `error.communication` are events the chart takes from its internal
  #   queue, seen by a host only in what the chart does next, or, for a
  #   chart started with `trace: true`, as a {Trace::EventDequeued}. The
  #   one failure answered as an effect is a {BudgetExhausted}: a macrostep
  #   spent its round budget, and the driver then queues external events
  #   without taking them.
  # - A {Child} carries an effect an invoked child answered, tagged with the
  #   child's session id; a child's own child's effect is tagged with its
  #   own.
  module Effect
    # A `<log>`: `label` as written, nil when it was not, and `value`, the
    # evaluated `expr`, nil for a `<log>` without one.
    Log = ::Data.define(:label, :value, :c_index, :owner, :macrostep, :microstep, :round)

    # A `<send>` with no delay, for the host to deliver now. `event`,
    # `target` and `type` are the resolved values, nil when the element
    # wrote neither attribute of the pair; `data` is the payload;
    # `send_id` is always set, generated when the author named none, and
    # `id_from_author?` is true when the element wrote `id` or
    # `idlocation`. `ordinal` is set only for a type the host registered: the
    # timer counter as this send advanced it.
    Send = ::Data.define(
      :event, :target, :type, :data, :send_id, :c_index, :owner, :macrostep, :microstep, :round, :ordinal,
      :id_from_author?
    )

    # A `<send>` with a delay, for the host to schedule `delay_ms`
    # milliseconds from now: every field of {Send}, the delay, an `ordinal`
    # that is always set, and `caller_context`, the opaque value the host
    # attached to the step, the same object it attached (never copied or
    # frozen), nil when it attached none.
    SendDelayed = ::Data.define(
      :event, :target, :type, :data, :send_id, :delay_ms, :c_index, :owner, :macrostep, :microstep, :round,
      :ordinal, :id_from_author?, :caller_context
    )

    # A `<cancel>`: the host drops the pending delayed send `send_id` names,
    # if any. `ordinal` and `caller_context` as {SendDelayed}'s.
    Cancel = ::Data.define(:send_id, :c_index, :owner, :macrostep, :microstep, :round, :ordinal, :caller_context)

    # One write to the datamodel: `location_path` the path written (a String
    # key or an Integer index per segment, the root first),
    # `location_source` the location as written, `new_value` and
    # `prior_value` the values at the path after and before. A write by
    # content carries its `c_index` and `owner` and a nil `d_index`; a
    # `<data>` that binds carries its `d_index`, its id as the one-segment
    # path and the source, and a nil `c_index` and `owner`. The two writes
    # no content node makes carry a nil `c_index` and `d_index`: an
    # `<invoke>`'s `idlocation` write, owned by `{kind: :invoke,
    # state_index:, invoke_index:}`, and each write an empty `<finalize>`
    # makes, owned by `{kind: :finalize, state_index:, invoke_index:}`.
    DatamodelChange = ::Data.define(
      :location_path, :location_source, :new_value, :prior_value, :d_index, :c_index, :owner, :macrostep,
      :microstep, :round
    )

    # An `<invoke>` started, for the driver to start its service. `type`
    # and `src` are the resolved values, nil when the element wrote neither
    # attribute of the pair; `params` is the `namelist` and `<param>` values
    # as data (`Predicator::UNDEFINED` for none); `content` the `<content>`
    # child's data, nil when it has none; `autoforward` the attribute;
    # `invoke_id` always set, generated when the author named none;
    # `state_index` the invoking state and `invoke_index` the element's
    # position among that state's `<invoke>`s; and `caller_context` as
    # {SendDelayed}'s.
    Invoke = ::Data.define(
      :invoke_id, :type, :src, :params, :content, :autoforward, :state_index, :invoke_index, :macrostep,
      :microstep, :round, :caller_context
    )

    # A live invocation is cancelled: its invoking state, `state_index`,
    # exits (or the chart stops) before it answered. `caller_context` as
    # {SendDelayed}'s.
    CancelInvoke = ::Data.define(:invoke_id, :state_index, :macrostep, :microstep, :round, :caller_context)

    # An external event forwarded, unchanged, to the live invocation
    # `invoke_id` names, whose `<invoke>` sets `autoforward`; `state_index`
    # is its invoking state and `event` the {Event} whole.
    Autoforward = ::Data.define(:invoke_id, :state_index, :event, :macrostep, :microstep, :round)

    # An effect an invoked child's run answered, as the driver reports it
    # among a call's effects: `session_id`, the child's session id (its
    # parent's, a dot and the invoke id), and `effect`, the effect itself. A
    # child's own child's effect is reported the same way, under its own
    # session id.
    Child = ::Data.define(:session_id, :effect)

    # The datamodel as the chart starts, before any `<data>` binds: the
    # host's values, the system variables over them and every `<data>` id
    # the host did not supply, declared undefined. Answered first when a
    # chart starts.
    DatamodelInit = ::Data.define(:datamodel, :macrostep, :microstep, :round)

    # A macrostep spent its round budget without reaching a stable
    # configuration: `configuration`, the state indexes active where the
    # last round left them, in document order; `budget`, the budget spent (a
    # count, or `:infinity`); and `pending_internal_events`, the {Event}s
    # still queued, oldest first. The chart keeps running.
    BudgetExhausted = ::Data.define(:configuration, :budget, :pending_internal_events, :macrostep, :microstep,
                                    :round)

    # The chart stopped. `donedata` is the top-level final's `<donedata>`
    # (`Predicator::UNDEFINED` when it has none, or it failed), nil when no
    # top-level final was active; `donedata_error`, the data of the first
    # `error.execution` that folding it raised, else nil; and
    # `configuration`, the state indexes active when it stopped, in document
    # order. Answered last.
    Done = ::Data.define(:donedata, :donedata_error, :configuration, :macrostep, :microstep, :round)

    # The trace effects, ported field for field from the reference's
    # (`Statifier.Effect.Trace.*`): diagnostics the loop answers only for a
    # state started with `trace: true`, each stamped with the counters as
    # they stood at the phase it reports. Configurations and index lists
    # are frozen Arrays in the order the reference gives.
    module Trace
      # One selection round's written conditions, in walk order: each a
      # `{t_index:, outcome:, reason:}` Hash, `outcome` `:enabled`,
      # `:disabled` or `:error` (with its `reason`). Answered only when the
      # round evaluated one.
      CondsEvaluated = ::Data.define(:evaluations, :macrostep, :microstep, :round)

      # A block of content ran: its `owner` (a content owner, or
      # `{kind: :global_script, index:}` for a `<script>` child of
      # `<scxml>`) and `c_indexes`, the nodes that ran, the failing one
      # included.
      ContentExecuted = ::Data.define(:owner, :c_indexes, :macrostep, :microstep, :round)

      # The chart stopped: {Effect::Done}'s fields, just before it.
      Done = ::Data.define(:donedata, :donedata_error, :configuration, :macrostep, :microstep, :round)

      # The states a microstep enters, in entry order (`indexes`), and the
      # `configuration` once they have entered.
      EntrySet = ::Data.define(:indexes, :configuration, :macrostep, :microstep, :round)

      # An {Event} was taken, `from` `:external` or `:internal`.
      EventDequeued = ::Data.define(:event, :from, :macrostep, :microstep, :round)

      # The states a microstep exits (or the chart's stop leaves), in exit
      # order (`indexes`), and the `configuration` once they have left.
      ExitSet = ::Data.define(:indexes, :configuration, :macrostep, :microstep, :round)

      # The pass over live invocations an external event makes before
      # selection: the `event`, the invoke ids `finalized` and those
      # `forwarded` to.
      FinalizeAutoforward = ::Data.define(:event, :finalized, :forwarded, :macrostep, :microstep, :round)

      # The invoke pass at the end of a stable macrostep: the states it
      # walked (`state_indexes`, entry order) and the `invoke_ids` it
      # started.
      InvokePass = ::Data.define(:state_indexes, :invoke_ids, :macrostep, :microstep, :round)

      # A macrostep reached a stable configuration with the chart running.
      MacrostepStable = ::Data.define(:configuration, :macrostep, :microstep, :round)

      # A selection: the `t_indexes` it took (empty included) and the
      # `event` it selected on, nil for an eventless round.
      TransitionsSelected = ::Data.define(:t_indexes, :event, :macrostep, :microstep, :round)
    end
  end
end
