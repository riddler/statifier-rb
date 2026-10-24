# frozen_string_literal: true

module DatamodelHelper
  D = Internals::Datamodel
  U = Predicator::UNDEFINED
  ROOT = %(xmlns="http://www.w3.org/2005/07/scxml" version="1.0")

  # The machine of a chart around body; the compile must succeed.
  def machine(body = '<state id="s1"/><state id="s2"/>', attributes = %(#{ROOT} name="chart"))
    result = Statifier.compile(%(<scxml #{attributes}>#{body}</scxml>))
    flunk "expected a machine, got #{result.error.map(&:message)}" unless result.ok?
    result.value
  end

  # A context over host's roots with the system variables seeded, s1 (index
  # 1) active unless configuration says otherwise.
  def context(host = {}, configuration: [1], machine: self.machine, clock: nil)
    data = D::SystemVariables.seed(host, session_id: "sid", name: machine.name)
    D.context(data, machine, configuration, clock:)
  end

  def compiled(source) = Internals::Machine::Compiled.new(instructions: Predicator.compile!(source), source:)

  def program(source) = Internals::Machine::Program.new(instructions: Predicator.compile_program!(source), source:)

  # A datamodel's author roots: the system variables left out.
  def authored(data) = data.reject { |root, _value| root.start_with?("_") }
end
