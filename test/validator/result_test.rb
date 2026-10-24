# frozen_string_literal: true

require "json"
require "test_helper"
require_relative "validator_helper"

# The validator's contracts: the result a compiler consumes, errors and
# warnings apart, every check run, document order, frozen output, and every
# document of the vendored corpus validating clean, as the reference
# validates every one of them.
class ValidatorResultTest < Minitest::Test
  include ValidatorHelper

  CORPUS = File.expand_path("../../conformance/statifier", __dir__)

  # sabotage: answer the chart whatever the errors (value: document in
  # Validator.validate); the assert_nil on the value fails.
  def test_a_chart_that_fails_a_gating_check_is_answered_without_its_chart
    result = validate(doc(%(<state id="a"><transition target="b"/></state>)))

    refute_predicate result, :ok?
    assert_nil result.value
    assert_equal [:unresolved_target], result.errors.map(&:reason)
    assert_equal "transition target \"b\" does not resolve to a state in the document", result.errors.first.message
  end

  # sabotage: answer a copy of the chart (document.dup in
  # Validator.validate); the assert_same fails.
  def test_a_chart_that_passes_is_the_callers_own_chart_unchanged
    source = doc(%(<state id="a"><transition target="a"/></state>))
    chart = Statifier::Lowering.lower(Statifier::XML.parse(source).value, source).value
    result = Statifier::Validator.validate(chart, source)

    assert_predicate result, :ok?
    assert_same chart, result.value
    assert_empty result.warnings
  end

  # sabotage: break ties by the reverse of the check order ([offset,
  # -index] in Validator.run); the assert_equal on the reasons fails.
  def test_findings_are_in_document_order_and_the_check_order_at_one_offset
    source = doc(%(<state id="s"><invoke><finalize><raise event="e"/></finalize></invoke></state>) +
                 %(<final id="f"><history id="h"><transition target="f"/></history></final>), %(version="2"))
    result = validate(source)

    assert_equal %i[bad_namespace bad_version history_bad_parent final_has_states], result.errors.map(&:reason)
    assert_equal([1, 17, 112, 112], result.errors.map { _1.location.start_column })
    assert_equal [:finalize_forbidden_content], result.warnings.map(&:reason)
  end

  # sabotage: leave a detail's owner unfrozen (drop .freeze on a Hash value
  # in Findings.make); the assert fails.
  def test_findings_are_deeply_frozen
    result = validate(doc(%(<state id="a"><initial/><state id="b"/></state>)))

    assert Ractor.shareable?(result.errors)
    assert Ractor.shareable?(result.warnings)
  end

  # sabotage: quote a missing id as an empty string (`""` for nil in
  # Findings.inspect_value); the assert_equal on the messages fails.
  def test_messages_name_a_missing_id_as_the_reference_does
    source = doc(%(<history><transition target="b"/></history><state><initial/><state id="b"/></state>))

    assert_equal ["history nil must be a child of a compound <state> or <parallel>, not scxml",
                  "<initial> must have exactly one transition, found 0"], validate(source).errors.map(&:message)
  end

  # sabotage: read a binary source as it is tagged (return source from
  # Validator.utf8 for every encoding); the assert_equal fails on the raw
  # value, which then is not UTF-8.
  def test_a_source_tagged_binary_is_read_as_utf8
    source = doc(%(<state id="a"><transition type="s\u{e9}" target="a"/></state>)).b
    error = validate(source).errors.first

    assert_equal [:transition_bad_type, { raw: "s\u{e9}" }], [error.reason, error.detail]
  end

  # sabotage: read every datamodel as a typo (DATAMODELS = %w[]); the
  # assert_empty on the refused corpus documents fails.
  def test_every_scxml_document_in_the_vendored_corpus_validates_clean
    sources = corpus_sources
    refused = sources.filter_map do |name, source|
      result = validate(source)
      "#{name}: #{result.errors.map(&:message).join("; ")}" unless result.ok? && result.warnings.empty?
    end

    assert_operator sources.size, :>, 300
    assert_empty refused
  end

  # Every SCXML document of the vendored corpus, in all three suites and
  # under cases/, by name.
  def corpus_sources
    suites = %w[scion w3c statifier].flat_map do |suite|
      JSON.parse(File.read(File.join(CORPUS, "corpus", "#{suite}.json"))).fetch("cases").map do |item|
        ["#{suite}/#{item.fetch("id")}", item.fetch("source")]
      end
    end
    cases = Dir.glob(File.join(CORPUS, "cases", "**", "*.scxml"))
    suites + cases.map { [_1.delete_prefix("#{CORPUS}/"), File.read(_1)] }
  end
end
