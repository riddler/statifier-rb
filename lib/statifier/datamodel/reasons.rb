# frozen_string_literal: true

module Statifier
  module Datamodel
    # What an evaluation answered: `value`, or, as `error`, the reason it
    # failed. Read `ok?`, not the value: nil is predicator's null.
    #
    # @api private
    Evaluated = ::Data.define(:value, :error) do
      # @return [Boolean] whether the evaluation succeeded
      def ok? = error.nil?
    end

    # What a program run answered: `data`, the datamodel it leaves (the
    # writes made before a failure included), and `error`, the reason it
    # failed, nil when it did not.
    #
    # @api private
    Executed = ::Data.define(:data, :error) do
      # @return [Boolean] whether the run succeeded
      def ok? = error.nil?
    end

    # What a write to a location answered: the `context` it leaves, the
    # `path` the location resolved to and the `prior_value` that path held
    # before the write, or, as `error`, the reason it was refused (and the
    # other fields nil).
    #
    # @api private
    Written = ::Data.define(:context, :path, :prior_value, :error) do
      # @return [Boolean] whether the write was made
      def ok? = error.nil?
    end

    # The reasons a failure carries, each the data of the `error.execution`
    # it raises. A deferred compile refusal is carried as the
    # {Compiler::Error} itself, as the reference carries its compiler's.

    # Predicator refused: `source` is the expression's or the location's
    # text and `error` predicator's own error value, unwrapped.
    #
    # @api private
    EvaluatorError = ::Data.define(:source, :error)

    # A condition answered something other than true or false.
    #
    # @api private
    NonBooleanCond = ::Data.define(:value)

    # A write reached `root`, a system variable's root (underscore-prefixed).
    #
    # @api private
    SystemVariable = ::Data.define(:root)

    # A write named a location whose root the datamodel does not hold; a
    # write never declares a root.
    #
    # @api private
    UnboundLocation = ::Data.define(:location)

    # A location's text is not one assignment target.
    #
    # @api private
    InvalidLocation = ::Data.define(:location)

    # A location's bracket key is a computed expression, which the
    # reference refuses as an assignment target key; `message` is the
    # reference's.
    #
    # @api private
    ComputedKey = ::Data.define(:location) do
      # @return [String] the reference's message for the refusal
      def message = "Cannot use computed expression as assignment target key"
    end

    # A delay that is not one: text predicator's duration parser refuses, or
    # a value that is neither text nor a duration.
    #
    # @api private
    InvalidDelay = ::Data.define(:value)

    # A `<data>` value is a `src`, which the host resolves and nothing here
    # fetches.
    #
    # @api private
    SrcValue = ::Data.define(:src)
  end
end
