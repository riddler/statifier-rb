# frozen_string_literal: true

require "predicator"

require_relative "machine"
require_relative "datamodel/reasons"
require_relative "datamodel/reason_value"
require_relative "datamodel/system_variables"
require_relative "datamodel/stores"
require_relative "datamodel/program"
require_relative "datamodel/location"
require_relative "datamodel/data_binding"
require_relative "datamodel/delay"

module Statifier
  # The datamodel binding: how a chart's expressions reach predicator, the
  # one expression language, as they reach it in the reference.
  #
  # The datamodel is a Hash of String root to predicator value. Every
  # evaluation runs through `Predicator.evaluate` (a condition, a value) or
  # `Predicator.execute` (a `<script>` program) against a {Context}: the
  # datamodel, `In()` as a host function over the configuration the context
  # was built with, the unbound policy {UNBOUND} and the clock the host
  # passed for the call. A context is built per evaluation site and is never
  # kept: `In()` reads a configuration that moves at every microstep, and
  # `_event` is rewritten for every event.
  #
  # Nothing here raises on a failed evaluation. A failure is answered as a
  # value carrying its reason, and the interpreter turns it into the
  # `error.execution` platform event the reference raises (an {Event});
  # the `<data>` binding ({DataBinding}) answers its failures the same way.
  #
  # @api private
  module Datamodel
    # The unbound policy every evaluation passes: a load of a root the
    # datamodel does not hold fails at the load, as the reference evaluates.
    # A declared root with no value holds `Predicator::UNDEFINED` instead,
    # and reads as undefined.
    UNBOUND = :error

    # One evaluation site's view: `data`, the datamodel; `machine` and
    # `configuration` (the indexes of the active states), which `In()`
    # reads; and `clock`, the host's clock for the call, nil for
    # predicator's own.
    Context = ::Data.define(:data, :machine, :configuration, :clock) do
      # The context with `root` bound to `value`, everything else carried
      # over: safe only inside the evaluation site that built this context.
      def bind(root, value) = with(data: data.merge(root => value).freeze)

      # The options an evaluation of this context passes to predicator.
      def options = { functions: { "In" => Datamodel.in_state(machine, configuration) }, on_unbound: UNBOUND, clock: }
    end

    module_function

    # The context one evaluation site runs against.
    def context(data, machine, configuration, clock: nil) = Context.new(data:, machine:, configuration:, clock:)

    # `In(stateId)` over `configuration`: true when the id names a state of
    # `machine` that is active, false for an inactive state and for an id
    # the chart never declared, as the reference answers. It takes exactly
    # one argument.
    def in_state(machine, configuration)
      lambda do |state_id|
        index = machine.id_to_index[state_id]
        !index.nil? && configuration.include?(index)
      end
    end

    # Evaluates `expr` (a {Machine::Compiled}, a {Machine::Static} or a
    # {Machine::Invalid}) against `context`. A static value comes back
    # untouched; a compiled one runs through `Predicator.evaluate`; an
    # invalid one answers the compile refusal it carries, the deferral the
    # reference raises when the node runs.
    #
    # @return [Evaluated] the value, or the reason it failed
    def evaluate(context, expr)
      case expr
      when Machine::Static then Evaluated.new(value: expr.value, error: nil)
      when Machine::Invalid then Evaluated.new(value: nil, error: expr.error)
      else
        result = Predicator.evaluate(expr.instructions, context.data, **context.options)
        error = EvaluatorError.new(source: expr.source, error: result.error) unless result.ok?
        Evaluated.new(value: result.value, error:)
      end
    end

    # Evaluates a transition's condition: nil (none written) is true. A
    # condition that fails, or answers anything but true or false, answers
    # the failure; the specification treats both as false and requires
    # `error.execution` for both.
    #
    # @return [Evaluated] true or false, or the reason it failed
    def evaluate_cond(context, cond)
      return Evaluated.new(value: true, error: nil) if cond.nil?

      evaluated = evaluate(context, cond)
      return evaluated if !evaluated.ok? || [true, false].include?(evaluated.value)

      Evaluated.new(value: nil, error: NonBooleanCond.new(value: evaluated.value))
    end

    # Runs a `<script>` program against `context` ({Program.run}); an
    # {Machine::Invalid} program answers its compile refusal and writes
    # nothing.
    #
    # @return [Executed] the datamodel the program leaves, and the reason it
    #   failed, if it did
    def execute(context, program)
      return Executed.new(data: context.data, error: program.error) if program.is_a?(Machine::Invalid)

      Program.run(context, program)
    end

    # Whether `root` is a system variable's: the rule is the underscore
    # prefix, as the reference's, so it covers the four seeded variables and
    # any other root spelled that way.
    def system_root?(root) = root.is_a?(String) && root.start_with?("_")
  end
end
