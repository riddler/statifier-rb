# frozen_string_literal: true

require "json"
require "test_helper"
require_relative "compiler_helper"

# Statifier.compile: the whole pipeline, its result, the stage that
# refuses, the warnings a compiled chart keeps, the machine as a frozen
# value, and every document of the vendored corpus compiling.
class CompileTest < Minitest::Test
  include CompilerHelper

  CORPUS = File.expand_path("../../conformance/statifier", __dir__)

  # sabotage: answer an empty list as the error of a compiled chart (error: []
  # in Statifier.compile); the assert_predicate on ok? fails.
  def test_a_chart_compiles_to_a_result_carrying_its_machine
    result = Statifier.compile(doc('<state id="a"><transition event="e.go" target="b"/></state><final id="b"/>'))

    assert_kind_of Data, result
    assert_predicate result, :ok?
    assert_nil result.error
    assert_instance_of Internals::Machine, result.value
    assert_equal %w[a b], result.value.states.drop(1).map(&:id)
  end

  # sabotage: answer the reader's result in place of its error
  # (refused([parsed]) in Statifier.compile); the assert_equal on the classes
  # fails.
  def test_a_document_that_does_not_read_answers_the_readers_error
    result = Statifier.compile("<scxml")

    refute_predicate result, :ok?
    assert_nil result.value
    assert_equal [Internals::XML::ParseError], result.error.map(&:class)
  end

  # sabotage: answer the first lowering error only (lowered.errors.first(1) in
  # Statifier.chart); the assert_equal on the reasons fails.
  def test_a_document_that_does_not_lower_answers_every_lowering_error
    result = Statifier.compile(doc("<state><bogus/></state><nope/>"))

    assert_equal %i[unsupported_element unsupported_element], result.error.map(&:reason)
    assert_equal [Internals::Lowering::Error], result.error.map(&:class).uniq
  end

  # sabotage: compile the lowered chart without the validator's gate
  # (Compiler.compile(lowered.value) and no return in Statifier.chart); the
  # refute_predicate on ok? fails.
  def test_a_document_that_fails_a_gating_check_is_not_compiled
    result = Statifier.compile(doc('<state id="a"/>', 'xmlns="http://www.w3.org/2005/07/scxml" version="2.0"'))

    refute_predicate result, :ok?
    assert_nil result.value
    assert_equal([[Internals::Validator::Error, :bad_version]], result.error.map { [_1.class, _1.reason] })
  end

  # sabotage: keep the warnings off the machine (warnings: [] in
  # Statifier.chart); the assert_equal on the reasons fails.
  def test_a_warning_never_refuses_and_rides_on_the_machine
    result = Statifier.compile(doc('<state id="a"><invoke type="x"><finalize><raise event="e"/></finalize>' \
                                   "</invoke></state>"))

    assert_predicate result, :ok?
    assert_equal [:finalize_forbidden_content], result.value.warnings.map(&:reason)
  end

  # sabotage: leave the machine unfrozen (drop Ractor.make_shareable around
  # the machine in Compiler.compile); the first assert fails.
  def test_the_machine_and_the_errors_are_deeply_frozen
    m = machine('<datamodel><data id="x">[1, {"k": 2}]</data></datamodel><state id="a"><onentry>' \
                '<log expr="x[0] + 1"/></onentry><transition cond="x != null" target="a"/></state>')

    assert Ractor.shareable?(m)
    assert_predicate m.transitions.first.cond.instructions, :frozen?
    assert Ractor.shareable?(Statifier.compile(doc('<state id="a"><transition cond="(" target="a"/></state>')))
  end

  # sabotage: answer the first compile error only (sorted(...).first(1) in
  # Compiler.compile); the assert_equal on the owners fails.
  def test_every_compile_error_is_answered
    result = Statifier.compile(doc('<state id="a"><transition cond="(" target="a"/>' \
                                   '<transition cond=")" target="a"/></state>'))

    assert_equal([{ kind: :transition, t_index: 0 }, { kind: :transition, t_index: 1 }],
                 result.error.map { _1.detail[:owner] })
  end

  # sabotage: record an assign's refusal as a load-time error (load_time for
  # Expressions.deferred in Content#assign_value); the assert_predicate on ok?
  # fails.
  def test_a_chart_whose_only_defect_is_deferred_compiles
    assert_predicate Statifier.compile(doc('<state id="a"><onentry><assign location="x" expr="("/>' \
                                           "<script>(</script></onentry></state>")), :ok?
  end

  # sabotage: answer a refusal for a source that is not a String (return
  # refused([]) at the top of Statifier.compile); the assert_raises fails.
  def test_a_source_that_is_not_a_string_is_a_callers_bug
    assert_raises(TypeError) { Statifier.compile(:a) }
  end

  def sources
    suites = %w[scion w3c statifier].flat_map do |suite|
      JSON.parse(File.read(File.join(CORPUS, "corpus", "#{suite}.json"))).fetch("cases").map do |item|
        ["#{suite}/#{item.fetch("id")}", item.fetch("source")]
      end
    end
    suites + Dir.glob(File.join(CORPUS, "cases", "**", "*.scxml")).map do |path|
      [path.delete_prefix("#{CORPUS}/"), File.read(path)]
    end
  end

  # sabotage: compile a literal attribute as an expression
  # (Expressions.compile for the literal in Parts#pair); the assert_empty on
  # the refused documents fails.
  def test_every_scxml_document_in_the_vendored_corpus_compiles_to_a_frozen_machine
    all = sources
    refused = all.filter_map do |name, source|
      result = Statifier.compile(source)
      next "#{name}: not frozen" if result.ok? && !Ractor.shareable?(result.value)

      "#{name}: #{result.error.map(&:message).join("; ")}" unless result.ok?
    end

    assert_operator all.size, :>, 300
    assert_empty refused
  end
end
