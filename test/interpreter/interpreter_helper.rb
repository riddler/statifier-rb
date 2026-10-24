# frozen_string_literal: true

module InterpreterHelper
  I = Internals::Interpreter
  ROOT = %(xmlns="http://www.w3.org/2005/07/scxml" version="1.0")

  # The machine of a chart around body; the compile must succeed.
  def machine(body, attributes = ROOT)
    result = Statifier.compile(%(<scxml #{attributes}>#{body}</scxml>))
    flunk "expected a machine, got #{result.error.map(&:message)}" unless result.ok?
    result.value
  end

  # The index of the state written with id.
  def at(machine, id) = machine.id_to_index.fetch(id)

  # The indexes of ids, in document order.
  def indexes(machine, *ids) = ids.map { at(machine, _1) }.sort.freeze

  # The ids of indexes, the root as "scxml".
  def ids(machine, indexes) = indexes.map { machine.state(_1).id || "scxml" }

  # A snapshot of machine with the root and ids active, history given by
  # history id to the ids it recorded.
  def snapshot(machine, *active, history: {})
    recorded = history.to_h { |h, values| [at(machine, h), indexes(machine, *values)] }.freeze
    I::Snapshot.new(machine:, configuration: [0, *indexes(machine, *active)].sort.freeze, history: recorded)
  end

  # The transitions of the state id, in document order.
  def transitions_of(machine, id) = machine.state(at(machine, id)).transitions.map { machine.transitions.fetch(_1) }

  # The datamodel conditions run against: the system variables over host.
  def data(machine, host = {}) = Internals::Datamodel::SystemVariables.seed(host, session_id: "sid", name: machine.name)

  # The ids the transitions of a selection round leave from.
  def sources(machine, transitions) = transitions.map { machine.state(_1.source).id }

  # The selection round for the event name with the root and active ids
  # active: the ids its transitions leave from.
  def selected_sources(chart, name, *active)
    sources(chart, I::Selection.select_transitions(snapshot(chart, *active), name, data(chart)).transitions)
  end

  # The entry of transitions from snap, after their exit.
  def exit_then_enter(snap, transitions)
    exited = I::ExitEntry.exit_states(snap, transitions)
    I::ExitEntry.enter_states(snap.with(configuration: exited.configuration, history: exited.history), transitions)
  end
end
