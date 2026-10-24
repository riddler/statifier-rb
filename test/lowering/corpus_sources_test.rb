# frozen_string_literal: true

require "json"
require "test_helper"

# Every SCXML document the vendored corpus carries, in all three suites and
# under cases/, lowers without a refusal, as the reference lowers every one
# of them, and its chart is immutable through and through.
class LoweringCorpusSourcesTest < Minitest::Test
  ROOT = File.expand_path("../../conformance/statifier", __dir__)

  def sources
    suites = %w[scion w3c statifier].flat_map do |suite|
      JSON.parse(File.read(File.join(ROOT, "corpus", "#{suite}.json"))).fetch("cases").map do |item|
        ["#{suite}/#{item.fetch("id")}", item.fetch("source")]
      end
    end
    suites + Dir.glob(File.join(ROOT, "cases", "**", "*.scxml")).map { [_1.delete_prefix("#{ROOT}/"), File.read(_1)] }
  end

  # sabotage: answer Errors.unsupported for "send" (drop it from BUILDERS);
  # the assert_empty on the refused documents fails.
  def test_lowers_every_scxml_document_in_the_vendored_corpus
    all = sources
    refused = all.filter_map do |name, source|
      result = Internals::Lowering.lower(Internals::XML.parse(source).value, source)
      "#{name}: #{result.errors.map(&:message).join("; ")}" unless result.ok?
    end

    assert_operator all.size, :>, 300
    assert_empty refused
  end

  # sabotage: leave the split parts of a list attribute unfrozen (drop
  # map(&:freeze) in Reading.list); the assert_empty on the documents that
  # are not shareable fails.
  def test_every_corpus_chart_is_deeply_frozen
    open = sources.reject do |_name, source|
      Ractor.shareable?(Internals::Lowering.lower(Internals::XML.parse(source).value, source))
    end

    assert_empty open.map(&:first)
  end
end
