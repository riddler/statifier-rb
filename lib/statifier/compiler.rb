# frozen_string_literal: true

require "predicator"

require_relative "document"
require_relative "machine"
require_relative "validator"
require_relative "compiler/error"
require_relative "compiler/expressions"
require_relative "compiler/numbering"
require_relative "compiler/content"
require_relative "compiler/parts"
require_relative "compiler/walk"

module Statifier
  # The validated chart in, the {Machine} out: the fourth step of reading a
  # chart, a port of the reference's compiler.
  #
  # One walk ({Walk}) interns every state, transition, content node and
  # `<data>` to an index in document order, and every expression compiles
  # once, through predicator: conditions and values through
  # `Predicator.compile`, `<script>` bodies through
  # `Predicator.compile_program`. An expression predicator refuses is an
  # {Error} with the reason `:expression_compile_error`, or, for the classes
  # the reference defers (an `<assign>`'s `expr`, a `<data>`'s `expr`, a
  # `namelist` entry and a `<script>` body), a {Machine::Invalid} on the
  # node that fails when it runs.
  #
  # Collect-all: every load-time refusal is answered, in document order,
  # and the machine only when there is none.
  #
  # @api private
  module Compiler
    # What {Compiler.compile} answers: the {Machine} as `value`, or every
    # {Error}, in document order, as `errors`.
    Result = ::Data.define(:value, :errors) do
      # @return [Boolean] true when the chart compiled
      def ok? = errors.empty?
    end

    # Compiles a validated chart into its machine.
    #
    # @param document [Document] the chart {Validator.validate} answered
    # @param warnings [Array<Validator::Warning>] the validator's warnings,
    #   kept on the machine
    # @return [Result] the frozen {Machine}, or the {Error}s
    def self.compile(document, warnings: [])
      walk = Walk.new
      walk.root(document)
      transitions = walk.transitions
      errors = sorted(walk.groups.values.flatten)
      return Result.new(value: nil, errors: Ractor.make_shareable(errors)) unless errors.empty?

      Result.new(value: Ractor.make_shareable(machine(walk, transitions, document, warnings)), errors: Walk::EMPTY)
    end

    # The machine of a walk that found no refusal.
    def self.machine(walk, transitions, document, warnings)
      Machine.new(
        states: walk.states.freeze, id_to_index: walk.id_to_index.freeze, transitions:,
        data_elements: walk.data.freeze, global_scripts: global_scripts(document.scripts),
        **document.to_h.slice(:name, :datamodel, :binding, :location), warnings: warnings.dup.freeze
      )
    end

    # The `<script>` children of `<scxml>`, each compiled as a program.
    def self.global_scripts(scripts)
      scripts.each_with_index.map do |script, index|
        site = Expressions::Site.new(owner: { kind: :global_script, index: }, element: "script", attribute: nil,
                                     location: script.location)
        Expressions.program(script.text, site)
      end.freeze
    end

    # The errors in document order, the groups' order kept at one offset.
    def self.sorted(errors)
      errors.each_with_index.sort_by { |error, index| [error.location.start_offset, index] }.map(&:first)
    end

    private_class_method :machine, :global_scripts, :sorted
  end
end
