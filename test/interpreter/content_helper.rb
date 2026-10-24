# frozen_string_literal: true

require_relative "interpreter_helper"

# Runs a block of executable content written as an `<onentry>` of the state
# `a`, against a datamodel that declares x (1), l ([1, 2, 3]), m ({a: 1}), s
# ("hello") and u (no value).
module ContentHelper
  include InterpreterHelper

  C = Statifier::Interpreter::Content
  DM = Statifier::Datamodel
  E = Statifier::Effect
  OWNER = { kind: :onentry, state_index: 1, ordinal: 0 }.freeze
  DATAMODEL = <<~XML
    <datamodel><data id="x" expr="1"/><data id="l" expr="[1, 2, 3]"/><data id="m" expr="{'a': 1}"/>
      <data id="s" expr="'hello'"/><data id="u"/></datamodel>
  XML

  # The machine whose state `a` runs body on entry.
  def content_machine(body) = machine(%(#{DATAMODEL}<state id="a"><onentry>#{body}</onentry></state>))

  # The stamp every block here runs under.
  def stamp = C::Stamp.new(owner: OWNER, macrostep: 2, microstep: 3, round: 4, caller_context: nil)

  # The datamodel content_machine binds when it starts.
  def bound(chart, host = {})
    seeded = DM::SystemVariables.seed(host, session_id: "sid", name: chart.name)
    DM::DataBinding.start(DM.context(seeded, chart, [0])).data
  end

  # body run as one block with a and the root active.
  # `with` overrides the stamp's fields and `host` is the host's datamodel.
  def run_block(body, sends = Statifier::Interpreter::Send::SendState::INITIAL, with: {}, host: {})
    chart = content_machine(body)
    C.execute_block(DM.context(bound(chart, host), chart, [0, 1]), chart.state(1).onentry.first.content,
                    stamp.with(**with), sends)
  end

  # The origin of an event the node at c_index raised.
  def origin(c_index) = { kind: :content, c_index:, owner: OWNER }

  # A failure of the node at c_index inside an if or a foreach: a write to
  # the undeclared root name, or `reason` when given.
  def nested_at(c_index, name = "zz", reason: DM::UnboundLocation.new(location: name))
    C::NestedContent.new(c_index:, reason:)
  end

  # The names of the events a block raised, in order.
  def raised_names(outcome) = outcome.raised.map(&:name)

  # What each event a block raised carries: a failure's data, a raised
  # event's name.
  def reasons(outcome) = outcome.raised.map { _1.name.start_with?("error.") ? _1.data : _1.name }

  # An event's origin and data.
  def origin_and_data(event) = [event.cause.origin, event.data]

  # A failure reason as the data of the event it raises.
  def rv(reason) = DM::ReasonValue.of(reason)

  # The effects of one class.
  def effects_of(outcome, klass) = outcome.effects.grep(klass)
end
