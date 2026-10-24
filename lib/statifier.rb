# frozen_string_literal: true

require_relative "statifier/version"
require_relative "statifier/xml"
require_relative "statifier/lowering"
require_relative "statifier/validator"
require_relative "statifier/compiler"
require_relative "statifier/datamodel"
require_relative "statifier/interpreter"
require_relative "statifier/driver"

# The interpreter core of an SCXML statechart engine.
#
# The package is being rewritten for 0.1.0. {Statifier.compile} reads SCXML
# source into a machine, through the reader ({Statifier::XML}), the lowering
# ({Statifier::Lowering}), the validator ({Statifier::Validator}) and the
# compiler ({Statifier::Compiler}), all internal. The driver
# ({Statifier::Driver}) steps a machine: {Statifier.start} starts a chart,
# {Statifier.step} sends it an event, {Statifier.advance} moves its virtual
# clock, and {Statifier.configuration} and {Statifier.done?} read it. The
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
  #     {Driver::DoneStatus}. Nil when the call was refused
  # @!attribute [r] error
  #   @return [Array, Symbol, nil] nil when the call succeeded. For
  #     {Statifier.compile}, the refusals, a frozen list that is never
  #     empty; for a driver call, the reason as a Symbol
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
  # its warnings on the machine.
  #
  # The machine is a frozen value, deeply, and its shape is internal: a host
  # hands it on and reads none of its members.
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
end
