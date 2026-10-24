# frozen_string_literal: true

require_relative "document"
require_relative "lowering"
require_relative "validator/error"
require_relative "validator/context"
require_relative "validator/states"
require_relative "validator/history"
require_relative "validator/data"
require_relative "validator/executable"
require_relative "validator/attributes"

module Statifier
  # The typed chart in, the chart or every error it carries out: the third
  # step of reading a chart, a port of the reference's validator, and the
  # gate in front of the compiler. A chart with an error is not compiled.
  #
  # Lowering keeps what was written, including shapes the specification
  # forbids; the validator holds that chart to the rules lowering leaves to
  # it. It also answers warnings, findings that do not gate compilation.
  # Four contracts, the reference's own:
  #
  # - Collect-all. Every check runs over the whole chart on every call; a
  #   chart that breaks five rules answers five errors.
  # - Document order. The errors, and separately the warnings, are sorted by
  #   where they start; findings at one offset keep the order the checks
  #   ran in.
  # - Never a partial result. The chart is answered only when there is no
  #   error, and it is the caller's own chart, unchanged.
  # - Both channels always. The warnings are answered whether or not an
  #   error is.
  #
  # No check here parses an expression: a `cond` or an `expr` is checked
  # when the chart is compiled, as the reference checks it there.
  #
  # @api private
  module Validator
    # The checks that gate compilation, in the reference's order: it decides
    # the order of errors at one offset.
    CHECKS = [
      [States, :ids], [States, :targets], [States, :initial_targets], [States, :initial_elements],
      [History, :histories], [History, :finals], [History, :final_parents], [History, :default_entries],
      [DataChecks, :donedata], [DataChecks, :contents], [DataChecks, :params], [Enums, :boilerplate],
      [Enums, :enums], [DataChecks, :data], [Executable, :assigns], [Executable, :ifs], [Executable, :scripts],
      [Executable, :invokes], [Executable, :sends_check], [Executable, :cancels], [Attributes, :duplicates]
    ].freeze

    # The checks whose findings are warnings.
    WARNING_CHECKS = [[Executable, :finalize_warnings]].freeze

    # What {Validator.validate} answers: the chart as `value` when no check
    # found an error (nil otherwise), every {Error} as `errors` and every
    # {Warning} as `warnings`, each frozen and in document order.
    Result = ::Data.define(:value, :errors, :warnings) do
      # @return [Boolean] true when the chart may be compiled
      def ok? = errors.empty?
    end

    # The encodings whose strings are read from their bytes.
    READ_AS_BYTES = [Encoding::BINARY, Encoding::US_ASCII].freeze

    # Holds a lowered chart to every rule that gates compilation.
    #
    # @param document [Document] the chart {Lowering.lower} answered
    # @param source [String] the document it was read from: the enumerated
    #   attributes and the attributes of each tag are read back out of it
    # @param invoke_content_markup [Boolean] accept a root that declares no
    #   namespace, as inline invoke content markup is placed in the SCXML
    #   namespace; a root declaring another namespace is still refused
    # @return [Result] the chart, or its errors, and its warnings
    def self.validate(document, source, invoke_content_markup: false)
      context = Index.build(document, utf8(source), invoke_content_markup)
      errors = run(CHECKS, document, context)
      Result.new(value: errors.empty? ? document : nil, errors:, warnings: run(WARNING_CHECKS, document, context))
    end

    # Every finding of `checks`, sorted by start offset, the checks' order
    # kept at one offset.
    def self.run(checks, document, context)
      findings = checks.flat_map { |owner, check| owner.public_send(check, document, context) }
      findings.each_with_index.sort_by { |finding, index| [finding.location.start_offset, index] }.map(&:first).freeze
    end

    # The source as the reader read it, so that its byte offsets slice it.
    def self.utf8(source)
      return source if source.encoding == Encoding::UTF_8
      return source.dup.force_encoding(Encoding::UTF_8) if READ_AS_BYTES.include?(source.encoding)

      source.encode(Encoding::UTF_8)
    end

    private_class_method :run, :utf8
  end
end
