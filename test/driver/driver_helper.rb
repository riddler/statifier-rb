# frozen_string_literal: true

# Compiles charts and drives them through the public driver calls.
module DriverHelper
  E = Statifier::Effect
  T = Statifier::Effect::Trace

  ROOT = %(xmlns="http://www.w3.org/2005/07/scxml" version="1.0" datamodel="predicator")

  # A processor that records what it is handed, in order.
  class Recorder
    attr_reader :calls

    def initialize(entry: nil)
      @calls = []
      @entry = entry
    end

    def deliver(send, event, context) = @calls << [:deliver, send, event, context]

    def cancel(cancel, context) = @calls << [:cancel, cancel, context]

    def ioprocessors_entry(_type, context) = @entry&.merge("session" => context.session_id)
  end

  # The chart around body, compiled.
  def machine(body, attributes = ROOT)
    compiled = Statifier.compile(%(<scxml #{attributes}>#{body}</scxml>))
    flunk "the chart does not compile: #{compiled.error.map(&:reason)}" unless compiled.ok?
    compiled.value
  end

  # The value of a call that must succeed.
  def moved(result)
    flunk "expected the call to succeed, got #{result.error.inspect}" unless result.ok?
    result.value
  end

  # The chart around body started, its {Statifier::Driver::Moved}.
  def start(body, **) = moved(Statifier.start(machine(body), session_id: "s1", **))

  # The event `name` sent from `moved`'s state.
  def step(moved, name, **) = moved(Statifier.step(moved.state, name, **))

  # The clock moved `milliseconds` from `moved`'s state.
  def advance(moved, milliseconds, **) = moved(Statifier.advance(moved.state, milliseconds, **))

  # The active states' names.
  def active(moved) = Statifier.configuration(moved.state).value

  # The labels and values of the logs in `moved`'s effects, in order.
  def logs(moved) = moved.effects.grep(E::Log).map { [_1.label, _1.value] }
end
