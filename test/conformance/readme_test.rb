# frozen_string_literal: true

require "test_helper"
require_relative "registry"

# What the README's Conformance section should say, read from the registry,
# the vendored corpus and the provenance record rather than typed: the suite
# table, the sentence on the registry's size, the table of unclaimed cases and
# the tag, commit and hash the section names.
module ReadmeConformance
  # The README's Conformance section: from its heading to the next one.
  def self.section(readme) = readme[/^## Conformance\n(.*?)(?=^## )/m, 1].to_s

  # The rows of the first table in text whose header starts with first_header,
  # each as its cells; none when there is no such table.
  def self.rows(text, first_header)
    lines = text.lines.map(&:strip)
    start = lines.index { _1.start_with?("| #{first_header} ") }
    return [] unless start

    lines.drop(start + 2).take_while { _1.start_with?("|") }.map { |line| line.split("|")[1..].map(&:strip) }
  end

  def self.claimed_ids(registry) = registry.fetch("entries").map { _1.fetch("case_id") }

  def self.unclaimed_cases(corpus, registry) = corpus.cases.reject { claimed_ids(registry).include?(_1["id"]) }

  # [suite, claim, cases, claimed, unclaimed] for one claim.
  def self.claim_row(claim, cases, claimed)
    done = cases.count { claimed.include?(_1["id"]) }
    [cases.first["suite"], "`#{claim}`", cases.size.to_s, done.to_s, (cases.size - done).to_s]
  end

  # The suite table the README should carry: one row per claim, then the total.
  def self.expected_suite_rows(corpus, registry)
    claimed = claimed_ids(registry)
    per_claim = corpus.cases.group_by { |item| Conformance::Records.claim_of(item) }
    rows = Conformance::CLAIMS.map { |claim| claim_row(claim, per_claim.fetch(claim), claimed) }
    rows + [total_row(corpus.cases.size, claimed.size)]
  end

  def self.total_row(cases, claimed) = ["all", "", cases.to_s, claimed.to_s, (cases - claimed).to_s]

  # One sentence per place the unclaimed table disagrees with the cases the
  # registry leaves out.
  def self.unclaimed_problems(rows, expected)
    problems = []
    problems << "the unclaimed table lists #{rows.map(&:first).inspect}, not the unclaimed cases" \
      unless column(rows, 0) == expected.map { _1["id"] }
    problems << "an unclaimed case has no claim or no reason" unless rows.all? { _1.size == 3 && _1.none?(&:empty?) }
    problems << "an unclaimed case names the wrong claim" \
      unless column(rows, 1) == expected.map { Conformance::Records.claim_of(_1) }
    problems
  end

  # One column of a table's rows, without the code marks.
  def self.column(rows, index) = rows.map { _1[index].delete("`") }

  # One sentence per piece of the provenance record the section does not name.
  def self.record_problems(text, record)
    record.values_at("tag", "sha", "corpus_hash").reject { text.include?(_1) }.map { "the section does not name #{_1}" }
  end

  # One sentence per place the README's Conformance section disagrees with
  # the registry, the corpus or the provenance record; empty when it agrees.
  def self.problems(readme, corpus, registry, record)
    text = section(readme)
    problems = suite_problems(text, corpus, registry)
    problems + unclaimed_problems(rows(text, "Case"), unclaimed_cases(corpus, registry)) + record_problems(text, record)
  end

  # One sentence per place the suite table or the size sentence is wrong.
  def self.suite_problems(text, corpus, registry)
    expected = expected_suite_rows(corpus, registry)
    found = rows(text, "Suite")
    problems = []
    problems << "the suite table reads #{found.inspect}, not #{expected.inspect}" unless found == expected
    problems << "the section does not say the registry holds #{claimed_ids(registry).size} entries" \
      unless text.include?("The registry holds #{claimed_ids(registry).size} entries")
    problems
  end
end

# The README against the registry, the vendored corpus and the provenance
# record, and the checker against README texts that are wrong.
class ReadmeConformanceTest < Minitest::Test
  README = File.read(File.expand_path("../../README.md", __dir__))
  CORPUS = Conformance::Corpus.load
  REGISTRY = JSON.parse(File.read(Conformance::Registry::PATH))
  RECORD = JSON.parse(File.read(File.join(Conformance::ROOT, Conformance::PROVENANCE_FILE)))

  def problems(readme: README, registry: REGISTRY) = ReadmeConformance.problems(readme, CORPUS, registry, RECORD)

  # sabotage: change a count in the README's suite table; the assert_empty
  # fails.
  def test_the_readme_section_agrees_with_the_registry_the_corpus_and_the_record
    assert_empty problems
  end

  # sabotage: compare only the number of suite rows in problems; the
  # assert_match fails.
  def test_a_changed_claimed_count_is_a_problem
    readme = README.sub("| scion | `scion` | 119 | 119 | 0 |", "| scion | `scion` | 119 | 118 | 1 |")

    assert_match(/the suite table reads/, problems(readme:).join)
  end

  # sabotage: accept any text for the size sentence in problems; the
  # assert_match fails.
  def test_a_changed_entry_count_is_a_problem
    readme = README.sub("The registry holds 320 entries", "The registry holds 321 entries")

    assert_match(/does not say the registry holds 320 entries/, problems(readme:).join)
  end

  # sabotage: compare the unclaimed table by length only; the assert_match on
  # the swapped case fails.
  def test_an_unclaimed_case_missing_extra_or_swapped_is_a_problem
    missing = README.sub(%r{^\| `w3c/test552` .*\n}, "")
    swapped = README.sub("| `w3c/test552`", "| `w3c/test999`")
    extra = README.sub("| `w3c/test552`", "| `w3c/test999` | `w3c-mandatory` | because |\n| `w3c/test552`")

    [missing, swapped, extra].each { assert_match(/the unclaimed table lists/, problems(readme: _1).join) }
  end

  # sabotage: accept any unclaimed row in problems; the assert_match fails.
  def test_an_unclaimed_case_without_a_reason_is_a_problem
    readme = README.sub(%r{^(\| `w3c/test201` \| `w3c-optional` \|).*$}, "\\1  |")

    assert_match(/no claim or no reason/, problems(readme:).join)
  end

  # sabotage: accept any claim column in unclaimed_problems; the assert_match
  # fails.
  def test_an_unclaimed_case_under_the_wrong_claim_is_a_problem
    readme = README.sub("| `w3c/test201` | `w3c-optional` |", "| `w3c/test201` | `w3c-mandatory` |")

    assert_match(/names the wrong claim/, problems(readme:).join)
  end

  # sabotage: compare only the number of suite rows in problems; the
  # assert_match fails.
  def test_a_registry_that_claims_an_unclaimed_case_is_a_problem
    entries = REGISTRY.fetch("entries") + [{ "case_id" => "w3c/test552", "suite" => "w3c" }]

    assert_match(/the suite table reads/, problems(registry: REGISTRY.merge("entries" => entries)).join)
  end

  # sabotage: leave record_problems out of problems; the assert_match fails.
  def test_a_wrong_tag_in_the_readme_is_a_problem
    readme = README.gsub(RECORD["tag"], "v0.0.0")

    assert_match(/does not name #{Regexp.escape(RECORD["tag"])}/, problems(readme:).join)
  end

  def suite_body = ReadmeConformance.rows(ReadmeConformance.section(README), "Suite").map { _1.drop(2).map(&:to_i) }

  def test_the_suite_table_rows_and_total_add_up
    *body, total = suite_body

    assert_equal 4, body.size
    assert_equal(body.transpose.map(&:sum), total)
    body.each { |cases, claimed, unclaimed| assert_equal cases, claimed + unclaimed }
  end

  def test_the_suite_table_total_is_the_manifests_case_count
    assert_equal CORPUS.manifest.fetch("suites").sum { _1.fetch("case_count") }, suite_body.last.first
  end
end
