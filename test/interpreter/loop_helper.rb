# frozen_string_literal: true

require_relative "interpreter_helper"

# Starts charts on the interpreter's loop and reads what it answered.
module LoopHelper
  include InterpreterHelper

  L = Internals::Interpreter::Loop
  E = Statifier::Effect
  T = Statifier::Effect::Trace
  EV = Statifier::Event

  # The loop started over the chart around body.
  def start(body, attributes = ROOT, **)
    L.initialize(machine(body, attributes), session_id: "sid", **)
  end

  # The loop after the external event `name` (an {Event}, or a name) is
  # handled from `stepped`'s state; the step must run.
  def handle(stepped, event, **)
    event = EV.external(event) if event.is_a?(String)
    handled = L.handle_event(stepped.state, event, **)
    flunk "expected the event to be handled, got #{handled.error}" unless handled.ok?
    handled
  end

  # The labels and values of the logs in `effects`, in order.
  def logs(effects) = effects.grep(E::Log).map { [_1.label, _1.value] }

  # The ids of a state's active states, the root left out.
  def active(state) = ids(state.machine, state.configuration - [0])

  # Each event `effects` took, as its name, type, data, sendid and
  # origin.
  def dequeued(effects)
    effects.grep(T::EventDequeued).map(&:event).map { [_1.name, _1.type, _1.data, _1.sendid, _1.cause.origin] }
  end

  # The class names of `effects`, the trace effects prefixed with `T.`.
  def kinds(effects)
    effects.map { _1.class.name.sub("Statifier::Effect::Trace::", "T.").sub("Statifier::Effect::", "") }
  end
end
