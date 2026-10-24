# frozen_string_literal: true

require_relative "statifier/version"
require_relative "statifier/xml"
require_relative "statifier/lowering"
require_relative "statifier/validator"
require_relative "statifier/compiler"
require_relative "statifier/datamodel"
require_relative "statifier/interpreter"

# The interpreter core of an SCXML statechart engine.
#
# The package is being rewritten for 0.1.0. Today it compiles a chart:
# {Statifier.compile} reads SCXML source into a machine, through the reader
# ({Statifier::XML}), the lowering ({Statifier::Lowering}), the validator
# ({Statifier::Validator}) and the compiler ({Statifier::Compiler}), all
# internal. The interpreter that steps a machine ({Statifier::Interpreter})
# is internal too; the driver a host steps a chart with arrives with a later
# change.
module Statifier
  # What {Statifier.compile} answers: the compiled machine as `value`, or,
  # as `error`, every refusal of the first stage that refused.
  #
  # @!attribute [r] value
  #   @return [Machine, nil] the machine; nil when the compile failed
  # @!attribute [r] error
  #   @return [Array, nil] the refusals, a frozen list that is never empty
  #     when the compile failed; nil when it succeeded
  Result = ::Data.define(:value, :error) do
    # @return [Boolean] whether the chart compiled
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
end
