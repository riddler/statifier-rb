# frozen_string_literal: true

require "test_helper"
require_relative "registry"
require_relative "runner"

# The gap list the registry stage prints (Conformance::Runner.gap_lines):
# every case the registry does not claim, with the features it needs and
# where it stands in a run.
class GapListTest < Minitest::Test
  CORPUS = Conformance::Corpus.load
  ENTRIES = JSON.parse(File.read(Conformance::Registry::PATH)).fetch("entries")
  CLAIMED = ENTRIES.map { |entry| entry["case_id"] }
  UNCLAIMED = CORPUS.cases.reject { |item| CLAIMED.include?(item["id"]) }

  def lines(results = Conformance::Runner.run(CORPUS)) = Conformance::Runner.gap_lines(CORPUS, ENTRIES, results)

  def line_for(lines, id) = lines.find { _1.start_with?("conformance: gap: #{id} (") }

  # sabotage: list every case in gap_lines, claimed or not; the assert_equal
  # on the ids listed fails (the claimed scion cases appear).
  def test_names_every_unclaimed_case_in_corpus_order_and_no_claimed_one
    ids = lines.map { |line| line.delete_prefix("conformance: gap: ").split.first }

    assert_equal UNCLAIMED.map { |item| item["id"] }, ids
    assert_equal %w[w3c statifier], ids.map { |id| id.split("/").first }.uniq
  end

  # sabotage: leave the features out of the line in gap_lines; the
  # assert_equal on the first unclaimed case's line fails.
  def test_each_line_names_the_features_the_case_needs
    item = UNCLAIMED.find { |each| !each["required_features"].empty? }
    results = CORPUS.cases.to_h { |each| [each["id"], { "result" => "pass" }] }

    assert_equal "conformance: gap: #{item["id"]} (needs #{item["required_features"].join(", ")}): " \
                 "passes, not yet claimed", line_for(lines(results), item["id"])
  end

  # sabotage: print the reason for a pass in standing; the assert_equal on
  # the passing case's line fails.
  def test_a_line_says_whether_the_case_passes_or_why_it_fails
    passing, failing = UNCLAIMED.first(2).map { |item| item["id"] }
    results = CORPUS.cases.to_h { |item| [item["id"], { "result" => "fail", "reason" => "why" }] }
    results[passing] = { "result" => "pass" }
    found = lines(results)

    assert_match(/\): passes, not yet claimed\z/, line_for(found, passing))
    assert_match(/\): fails: why\z/, line_for(found, failing))
  end

  # sabotage: join the empty feature list in needs; the assert_includes on
  # "no feature" fails.
  def test_a_case_with_no_required_feature_says_so
    bare = CORPUS.cases.find { |item| item["required_features"].empty? }
    results = CORPUS.cases.to_h { |item| [item["id"], { "result" => "pass" }] }

    assert_includes line_for(Conformance::Runner.gap_lines(CORPUS, [], results), bare["id"]),
                    "(needs no feature): passes"
  end
end
