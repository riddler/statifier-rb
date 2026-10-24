# frozen_string_literal: true

require "json"
require "test_helper"

# Every SCXML document the vendored corpus carries, in all three suites and
# under cases/, reads without a refusal. The reference reads every one of
# them, so a refusal here would fail a corpus case later. Their structure is
# the compiler's to assert, not this test's.
class CorpusSourcesTest < Minitest::Test
  ROOT = File.expand_path("../../conformance/statifier", __dir__)

  def sources
    suites = %w[scion w3c statifier].flat_map do |suite|
      JSON.parse(File.read(File.join(ROOT, "corpus", "#{suite}.json"))).fetch("cases").map do |item|
        ["#{suite}/#{item.fetch("id")}", item.fetch("source")]
      end
    end
    suites + Dir.glob(File.join(ROOT, "cases", "**", "*.scxml")).map { [_1.delete_prefix("#{ROOT}/"), File.read(_1)] }
  end

  # sabotage: refuse the XML declaration in skip_processing_instruction
  # (treat target "xml" as misplaced everywhere); the assert_empty on the
  # refused documents fails.
  def test_reads_every_scxml_document_in_the_vendored_corpus
    all = sources
    refused = all.filter_map do |name, source|
      result = Internals::XML.parse(source)
      "#{name}: #{result.error.message}" unless result.ok?
    end

    assert_operator all.size, :>, 300
    assert_empty refused
  end
end
