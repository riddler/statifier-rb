# frozen_string_literal: true

require_relative "statifier/version"
require_relative "statifier/xml"
require_relative "statifier/lowering"
require_relative "statifier/validator"
require_relative "statifier/compiler"
require_relative "statifier/datamodel"
require_relative "statifier/interpreter"
require_relative "statifier/driver"
require_relative "statifier/position"

# The interpreter core of an SCXML statechart engine.
#
# The package is being rewritten for 0.1.0. {Statifier.compile} reads SCXML
# source into a machine, through the reader ({Statifier::XML}), the lowering
# ({Statifier::Lowering}), the validator ({Statifier::Validator}) and the
# compiler ({Statifier::Compiler}), all internal. The driver
# ({Statifier::Driver}) steps a machine: {Statifier.start} starts a chart,
# {Statifier.step} sends it an event, {Statifier.advance} moves its virtual
# clock, {Statifier.report_send_failed} tells it a send failed, and
# {Statifier.configuration} and {Statifier.done?} read it.
# {Statifier.export_position} writes a chart's execution out as plain data a
# host can keep, and {Statifier.import_position} reads it back in. The
# interpreter under the driver ({Statifier::Interpreter}) is internal.
#
# Every one of those calls answers a {Result}. Nothing is kept between
# calls but the state a call answers: there is no global configuration, and
# a host passes its processors and its clock with every call.
module Statifier
  # What every public call answers: its `value`, or, as `error`, why it
  # was refused.
  #
  # @!attribute [r] value
  #   @return [Object, nil] {Statifier.compile}'s machine; the
  #     {Driver::Moved} a driver call that moves a chart answers;
  #     {Statifier.configuration}'s list of names; {Statifier.done?}'s
  #     {Driver::DoneStatus}; {Statifier.export_position}'s position;
  #     {Statifier.import_position}'s {Driver::State}. Nil when the call was
  #     refused
  # @!attribute [r] error
  #   @return [Array, Symbol, Position::Refusal, nil] nil when the call
  #     succeeded. For {Statifier.compile}, the refusals, a frozen list that
  #     is never empty; for a driver call, the reason as a Symbol; for
  #     {Statifier.export_position} and {Statifier.import_position}, a
  #     {Position::Refusal}
  Result = ::Data.define(:value, :error) do
    # @return [Boolean] whether the call succeeded
    def ok? = error.nil?
  end

  # Compiles SCXML source into a machine: the document is read, lowered,
  # validated and compiled, in that order, and the first stage that refuses
  # it stops the rest.
  #
  # A refused source answers a failed {Result} whose `error` is the list of
  # that stage's refusals, in document order: the reader's one
  # `Statifier::XML::ParseError`, or every `Statifier::Lowering::Error`, or
  # every `Statifier::Validator::Error`, or every
  # `Statifier::Compiler::Error` (an expression predicator refused). Each
  # carries a `reason` symbol, a `message` for a person and a `location`, the
  # span in the source it names; all but the reader's carry a `detail` Hash
  # too. A validator warning never refuses: a chart that compiles carries
  # its warnings on the machine, as the reference's machine does.
  #
  # The machine is a frozen value, deeply, and its shape is internal: a host
  # hands it on and reads one of its members only, `warnings`, the
  # validator's warnings in document order, a frozen list of
  # `Statifier::Validator::Warning` values, each with the `reason`,
  # `detail`, `message` and `location` an error carries (empty for a chart
  # with none).
  #
  # @example
  #   result = Statifier.compile(<<~SCXML)
  #     <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0">
  #       <state id="a"><transition event="e.go" target="b"/></state>
  #       <final id="b"/>
  #     </scxml>
  #   SCXML
  #   result.ok? # => true
  #
  # @param source [String] the SCXML document
  # @return [Result] the machine, or the refusals
  # @raise [TypeError] when `source` is not a String
  def self.compile(source)
    parsed = XML.parse(source)
    return refused([parsed.error]) unless parsed.ok?

    compiled = chart(parsed.value, source)
    compiled.ok? ? Result.new(value: compiled.value, error: nil) : refused(compiled.errors)
  end

  # The read tree lowered, validated and compiled: the result of the last
  # stage that ran, each stage's result answering `ok?`, `value` and
  # `errors`.
  def self.chart(root, source)
    lowered = Lowering.lower(root, source)
    return lowered unless lowered.ok?

    validated = Validator.validate(lowered.value, source)
    return validated unless validated.ok?

    Compiler.compile(validated.value, warnings: validated.warnings)
  end

  # A failed {Result} carrying `errors`.
  def self.refused(errors) = Result.new(value: nil, error: Ractor.make_shareable(errors.dup))

  private_class_method :chart, :refused

  # Starts a chart: its datamodel bound, its initial states entered, and the
  # chart run, with every event it queues for itself, to a stable
  # configuration.
  #
  # @example
  #   machine = Statifier.compile(<<~SCXML).value
  #     <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0">
  #       <state id="a"><transition event="e.go" target="b"/></state>
  #       <final id="b"/>
  #     </scxml>
  #   SCXML
  #   started = Statifier.start(machine, session_id: "s1")
  #   Statifier.configuration(started.value.state).value # => ["a"]
  #
  # @param machine [Machine] a compiled chart
  # @param options [Hash] the keywords below, each optional
  # @option options [String, nil] :session_id the session's id, which
  #   `_sessionid` reads; the driver mints one (`sess_` and 26 base32
  #   symbols) when nil
  # @option options [Hash{String => Object}] :datamodel the datamodel's
  #   starting values, under the system variables; copied, never frozen in
  #   place
  # @option options [Hash{String => #deliver}] :processors the host's
  #   processor for each send type it registers ({Statifier::Driver} says
  #   what each is handed); every later call names the same types
  # @option options [Integer, Symbol] :max_macrostep_rounds the rounds one
  #   macrostep may spend, a positive Integer or `:infinity`; 10000 when
  #   absent
  # @option options [Boolean] :trace whether the chart answers the trace
  #   effects ({Statifier::Effect::Trace}); false when absent
  # @option options [#call, nil] :clock the clock predicator reads for the
  #   call; its own when nil
  # @return [Result] a {Driver::Moved}: the state and the effects
  # @raise [TypeError] for a machine, session id or processors of the wrong
  #   kind
  # @raise [ArgumentError] for an option it does not name, or a round
  #   budget that is neither a positive Integer nor `:infinity`
  def self.start(machine, **options)
    raise TypeError, "expected a compiled machine, got #{machine.class}" unless machine.is_a?(Machine)

    Driver::Calls.start(machine, options)
  end

  # Sends the chart one external event, and runs it, and every event it
  # queues for itself, to a stable configuration. While a macrostep's round
  # budget has halted the chart, the event is queued and not taken.
  #
  # @param state [Driver::State] what the last call answered
  # @param name [String] the event's name
  # @param data [Object] the event's data, `Predicator::UNDEFINED` for none
  # @param processors [Hash{String => #deliver}] as {start} took them
  # @param clock [#call, nil] as {start} took it
  # @return [Result] a {Driver::Moved}, or the error `:not_running` once
  #   the chart has stopped
  # @raise [TypeError] for a state or a name of the wrong kind
  # @raise [ArgumentError] for processors that name other types than the
  #   chart was started with
  def self.step(state, name, data: Predicator::UNDEFINED, processors: {}, clock: nil)
    Driver::Calls.step(state, name, data:, processors:, clock:)
  end

  # Moves the virtual clock `milliseconds` forward, firing every pending
  # timer due by then, earliest first and in the order they were scheduled
  # at one due time, each run to completion before the next.
  #
  # @param state [Driver::State] what the last call answered
  # @param milliseconds [Numeric] how far the clock moves, finite and not
  #   negative
  # @param processors [Hash{String => #deliver}] as {start} took them
  # @param clock [#call, nil] as {start} took it
  # @return [Result] a {Driver::Moved}, or the error `:invalid_duration`
  # @raise [TypeError] for a state of the wrong kind
  # @raise [ArgumentError] for processors that name other types than the
  #   chart was started with
  def self.advance(state, milliseconds, processors: {}, clock: nil)
    Driver::Calls.advance(state, milliseconds, processors:, clock:)
  end

  # Reports a send the host was handed and could not deliver:
  # `error.communication` joins the chart's internal queue, its origin the
  # send's content and its `sendid` the send's id whether or not its author
  # named it, and the chart runs to a stable configuration, then takes
  # whatever its external queue holds, as {step} does. The driver keeps no
  # table of the sends it handed, so the report is not checked against one:
  # it reaches the session `state` is for. A failure a processor knows of
  # while it is handed the send is answered from its `deliver` as a
  # {Driver::DeliveryFailure} instead, and fails the send within that call.
  #
  # Once the chart has stopped, or while a macrostep's round budget has
  # halted it, the report is refused and nothing is written, as the
  # reference's session drops it; the miss is then the host's to record.
  #
  # @example
  #   failed = Statifier.report_send_failed(machine, moved.state, send, processors:)
  #   failed.value.state # the chart after it took error.communication
  #
  # @param machine [Machine] the compiled chart `state` is an execution of
  # @param state [Driver::State] what the last call answered
  # @param send [Effect::Send, Effect::SendDelayed] the send the host's
  #   processor was handed
  # @param options [Hash] the keywords below, each optional
  # @option options [Object, nil] :reason the host's own account of the
  #   failure; not read, and the chart is not handed it
  # @option options [Hash{String => #deliver}] :processors as {start} took
  #   them
  # @option options [#call, nil] :clock as {start} took it
  # @return [Result] a {Driver::Moved}, or the error `:not_running` once the
  #   chart has stopped, or `:halted` while a round budget has halted it
  # @raise [TypeError] for a machine, a state or a send of the wrong kind
  # @raise [ArgumentError] for an option it does not name, a state that is
  #   not an execution of `machine`, or processors that name other types
  #   than the chart was started with
  def self.report_send_failed(machine, state, send, **options)
    Driver::Calls.report_send_failed(machine, state, send, options)
  end

  # The active states, by id, the `<scxml>` root left out, sorted; a state
  # the document gave no id is named `#` and its index. Empty once the
  # chart has stopped ({done?} names the states it stopped in).
  #
  # @param state [Driver::State] what a call answered
  # @return [Result] the names, a frozen list
  # @raise [TypeError] for a state of the wrong kind
  def self.configuration(state) = Driver::Calls.configuration(state)

  # Whether the chart has stopped and, once it has, the top-level final's
  # donedata and the states it stopped in, as the {Effect::Done} carried
  # them.
  #
  # @param state [Driver::State] what a call answered
  # @return [Result] a {Driver::DoneStatus}
  # @raise [TypeError] for a state of the wrong kind
  def self.done?(state) = Driver::Calls.done?(state)

  # Writes the chart's execution out as a position: plain data in the
  # reference's string-id vocabulary, a frozen Hash with String keys whose
  # values are Strings, Integers, booleans, and Arrays and Hashes of them,
  # ready for JSON ({Statifier::Position} says what each key holds). A
  # datamodel value is carried as text in predicator's tagged-value
  # encoding.
  #
  # A position holds what the interpreter holds between two calls and
  # nothing of the driver's own: no pending timer, no queued external
  # event, no send a processor holds, no virtual time and no donedata.
  #
  # @example
  #   started = Statifier.start(machine, session_id: "s1").value
  #   position = Statifier.export_position(started.state).value
  #   position["configuration"] # => ["a"]
  #
  # @param state [Driver::State] what a call answered
  # @return [Result] the position, or a {Position::Refusal}:
  #   `:internal_queue_not_empty` while an internal event waits;
  #   `:unnameable_states`, every index (`detail[:indexes]`, sorted) of a
  #   state the position holds that the document gave no id; or
  #   `:unencodable_value`, the first variable (`detail[:field]`) whose
  #   value the tagged-value encoding refuses, with the codec's reason
  # @raise [TypeError] for a state of the wrong kind
  def self.export_position(state) = Position.export(Driver::Checks.state(state, nil))

  # Reads a position back in as a driver state over `machine`, which may be
  # a fresh compile of the same source or any machine holding every state
  # the position names: the position's chart is not checked, as the
  # reference's import checks none. The ids are resolved against `machine`,
  # the root re-added, and the driver's own members start as a fresh start
  # leaves them: the virtual clock at zero, no pending timer, nothing
  # queued or held. The session id is the one `_sessionid` holds. A stopped
  # position imports stopped, its donedata undefined and its configuration
  # empty. The position is read, never frozen or changed.
  #
  # @example
  #   imported = Statifier.import_position(machine, JSON.parse(JSON.generate(position)))
  #   Statifier.configuration(imported.value).value # => ["a"]
  #
  # @param machine [Machine] a compiled chart
  # @param position [Hash] what {export_position} answered, or the same
  #   data read back from JSON
  # @param processors [Hash{String => #deliver}] the host's processors, as
  #   {start} takes them; every later call names the same types
  # @return [Result] the {Driver::State}, or a {Position::Refusal}:
  #   `:malformed_export` when `position` is not a Hash
  #   (`detail[:kind]` `:not_a_hash`), lacks a key (`:missing_keys`, every
  #   one in `detail[:keys]`, sorted), holds a field of the wrong shape
  #   (`:bad_shape`, the first in `detail[:field]`), a datamodel text that
  #   does not decode (`:undecodable_value`) or no String `_sessionid`
  #   (`:no_session_id`); or `:unknown_state_ids`, every id `machine` holds
  #   no state for (`detail[:ids]`, sorted)
  # @raise [TypeError] for a machine or processors of the wrong kind
  def self.import_position(machine, position, processors: {})
    raise TypeError, "expected a compiled machine, got #{machine.class}" unless machine.is_a?(Machine)

    Position.import(machine, position, processors)
  end
end
