# frozen_string_literal: true

module Statifier
  # The effects executable content answers, ported field for field from the
  # reference's effect vocabulary (`Statifier.Effect.*` in statifier-ex):
  # plain data values a host reads, each a `Data` the block runner freezes
  # deeply, the values it carries included. The reference tags
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
  # The vocabulary is internal until the driver fixes the public surface.
  #
  # @api private
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
    # attached to the step, nil when it attached none.
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
    # content carries its `c_index` and `owner` and a nil `d_index`.
    DatamodelChange = ::Data.define(
      :location_path, :location_source, :new_value, :prior_value, :d_index, :c_index, :owner, :macrostep,
      :microstep, :round
    )
  end
end
