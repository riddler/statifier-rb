# frozen_string_literal: true

module CompilerHelper
  ROOT = %(xmlns="http://www.w3.org/2005/07/scxml" version="1.0")

  # A chart whose root carries the namespace and version, around body.
  def doc(body, attributes = ROOT) = %(<scxml #{attributes}>#{body}</scxml>)

  # The machine body compiles to; the compile must succeed.
  def machine(body, attributes = ROOT)
    result = Statifier.compile(doc(body, attributes))
    flunk "expected a machine, got #{result.error.map(&:message)}" unless result.ok?
    result.value
  end

  # The executable content of the first onentry block of the first state.
  def content_of(body) = machine(%(<state id="s"><onentry>#{body}</onentry></state>)).state(1).onentry.first.content

  # Each refusal of body as [reason, owner, element, attribute, source,
  # line, column]; the compile must fail at the compiler.
  def refusals(body)
    result = Statifier.compile(doc(body))
    refute_predicate result, :ok?, "expected #{body.inspect} to be refused"
    assert_nil result.value
    result.error.map { refusal_row(_1) }
  end

  # One compiler refusal as a row; it must be the compiler's.
  def refusal_row(error)
    assert_instance_of Statifier::Compiler::Error, error
    [error.reason, *error.detail.values_at(:owner, :element, :attribute, :source),
     error.location.start_line, error.location.start_column]
  end

  # A refusal row for an expression error.
  def row(owner, element, attribute, source, column)
    [:expression_compile_error, owner, element, attribute, source, 1, column]
  end

  # The column of `needle` in doc(body), from 1.
  def column_of(body, needle) = doc(body).index(needle) + 1
end
