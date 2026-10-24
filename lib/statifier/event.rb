# frozen_string_literal: true

module Statifier
  # An event, as the reference carries one (`Statifier.Event` in
  # statifier-ex): the one value every queue holds, whoever raised it.
  #
  # `name`; `type`, `:external`, `:internal` or `:platform` (provenance,
  # not routing: an internal and a platform event ride the same internal
  # queue); `data`, `Predicator::UNDEFINED` for an event with none (nil is
  # predicator's null); `cause`, the {Cause} of an event the chart raised,
  # nil for one the host sent; `invokeid`, `origin`, `origintype` and
  # `sendid`, the specification's `_event` fields, nil when the event
  # carries none; and `caller_context`, the opaque value a host attached to
  # an external event, carried as the same object and never read.
  #
  # A host meets one in the effects the driver answers and as the event a
  # processor is handed beside a send.
  Event = ::Data.define(:name, :type, :data, :cause, :invokeid, :origin, :origintype, :sendid, :caller_context)

  # The event's {Cause} and its constructors.
  class Event
    # Why the chart raised an event: `origin`, what raised it, and the
    # counters as they stood when it was raised. An origin is one of
    # `{kind: :content, c_index:, owner:}` (a content node, `owner` its
    # block), `{kind: :state, state_index:}` (a completion, or a failed
    # `<donedata>` `<content>`), `{kind: :transition, t_index:}` (a failed
    # condition), `{kind: :data, d_index:}` (a failed `<data>`),
    # `{kind: :donedata_param, state_index:, param_index:}`,
    # `{kind: :global_script, index:}`, `{kind: :invoke, state_index:,
    # invoke_index:}` (an `<invoke>` that failed to start) and
    # `{kind: :finalize, state_index:, invoke_index:}` (a write of an empty
    # `<finalize>` that failed).
    Cause = ::Data.define(:origin, :macrostep, :microstep, :round)

    # The fields an event the chart raised leaves blank.
    BLANK = { invokeid: nil, origin: nil, origintype: nil, caller_context: nil }.freeze

    # The optional fields of an event the host sends, as they stand when it
    # names none of them.
    EXTERNAL = { data: Predicator::UNDEFINED, sendid: nil, **BLANK }.freeze

    # An event the host sent: no cause, and each of {EXTERNAL}'s fields as
    # `fields` gives it.
    #
    # @return [Event]
    # @raise [ArgumentError] for a field an event does not have
    def self.external(name, **fields) = new(name:, type: :external, cause: nil, **EXTERNAL, **fields)

    # An event raised by a `<raise>`, or by a send to the internal queue:
    # `origin` and `origintype` are blank, as the specification requires of
    # an internal event.
    #
    # @return [Event]
    def self.internal(name, cause, data: Predicator::UNDEFINED, sendid: nil)
      new(name:, type: :internal, data:, cause:, sendid:, **BLANK)
    end

    # An event the platform raised: an `error.*` or a `done.state.*`.
    #
    # @return [Event]
    def self.platform(name, cause, data: Predicator::UNDEFINED, sendid: nil)
      new(name:, type: :platform, data:, cause:, sendid:, **BLANK)
    end

    private_constant :BLANK, :EXTERNAL
  end
end
