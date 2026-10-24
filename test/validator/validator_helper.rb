# frozen_string_literal: true

module ValidatorHelper
  ROOT = %(xmlns="http://www.w3.org/2005/07/scxml" version="1.0")

  # A chart whose root carries the namespace and version, around body.
  def doc(body, attributes = ROOT) = %(<scxml #{attributes}>#{body}</scxml>)

  # One line of source written in parts, so that each column is known.
  def cat(*parts) = parts.join

  # The validator's result for source, which must read and lower.
  def validate(source, **)
    parsed = Statifier::XML.parse(source)
    flunk "expected a parse, got #{parsed.error.message}" unless parsed.ok?
    lowered = Statifier::Lowering.lower(parsed.value, source)
    flunk "expected a chart, got #{lowered.errors.map(&:message)}" unless lowered.ok?
    Statifier::Validator.validate(lowered.value, source, **)
  end

  # Each error of source as [reason, detail, line, column].
  def errors_of(source, **) = rows(validate(source, **).errors)

  # Each warning of source as [reason, detail, line, column].
  def warnings_of(source) = rows(validate(source).warnings)

  def rows(findings)
    findings.map { [_1.reason, _1.detail, _1.location.start_line, _1.location.start_column] }
  end

  # The `owner` detail of a default transition's errors.
  def initial(id) = { kind: :initial, id: }
  def history(id) = { kind: :history, id: }
end
