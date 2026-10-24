# frozen_string_literal: true

require "test_helper"
require_relative "copy_helper"
require_relative "ratchet"
require_relative "runner"

# The ratchet (Conformance::Ratchet, rake ratchet), the only writer of
# conformance/registry.json: it writes from the results of a run of the whole
# corpus, adds what passed, refuses to drop what no longer passes, and with
# nothing passing writes the registry it found. Each test writes into a
# throwaway copy of conformance/; the shipped registry is never written.
class RatchetTest < Minitest::Test
  include Conformance::CopyHelper

  CORPUS = Conformance::Corpus.load
  A = "scion/actionSend/send1"
  M = "w3c/test144"

  def run_passing(*ids)
    Conformance::Runner.run(CORPUS, drive: ->(item) { ids.include?(item["id"]) ? :pass : "not this one" })
  end

  # Writes from results into a copy whose registry holds entries (nil for
  # the shipped one); answers the problems and the bytes left on disk.
  def ratchet(results, entries: nil)
    with_conformance_copy do |dir|
      path = File.join(dir, "registry.json")
      rewrite_json(dir, "registry.json") { |registry| registry["entries"] = entries } if entries
      problems = Conformance::Ratchet.write(path, CORPUS, results)
      return [problems, File.binread(path)]
    end
  end

  # sabotage: write JSON.pretty_generate(registry) in place of
  # Registry.encode(registry) in Ratchet.write; the assert_equal on the
  # written bytes fails.
  def test_a_run_that_passes_nothing_writes_the_same_empty_registry
    problems, bytes = ratchet(run_passing)

    assert_empty problems
    assert_equal File.binread(Conformance::Registry::PATH), bytes
  end

  # sabotage: drop the sort_by in Ratchet.next_registry; the assert_equal on
  # the entries' order fails (the recorded w3c entry is written first).
  def test_adds_every_observed_pass_sorted_with_its_claims
    problems, bytes = ratchet(run_passing(M, A), entries: [{ "case_id" => M, "suite" => "w3c" }])
    registry = JSON.parse(bytes)

    assert_empty problems
    assert_equal([A, M], registry["entries"].map { |entry| entry["case_id"] })
    assert_equal %w[scion w3c-mandatory], registry["claims"]
    assert_equal CORPUS.corpus_hash, registry["corpus_hash"]
    assert_empty Conformance::RegistryCheck.problems(bytes, CORPUS, run_passing(M, A))
  end

  # sabotage: make recorded_problems answer []; the assert_equal on the
  # refusal fails, and the entry is dropped from the file.
  def test_refuses_to_drop_a_recorded_entry_that_no_longer_passes
    recorded = [{ "case_id" => A, "suite" => "scion" }]
    problems, bytes = ratchet(run_passing(M), entries: recorded)

    assert_equal ["#{A} is recorded and did not pass in this run"], problems
    assert_equal recorded, JSON.parse(bytes)["entries"]
  end

  # sabotage: make run_problems answer [] whatever the results; the
  # assert_equal on the refusal of a partial run fails.
  def test_refuses_a_run_that_is_not_of_the_whole_corpus
    partial = run_passing(A).first(3).to_h
    problems, = ratchet(partial)

    assert_equal ["the run is not of the whole corpus: 3 results for #{CORPUS.cases.size} cases"], problems
  end

  # sabotage: drop the suite test from recorded_problems; the assert_equal
  # on the refusal of the entry under the wrong suite fails.
  def test_refuses_a_recorded_entry_under_another_suite_or_absent_from_the_corpus
    recorded = [{ "case_id" => "scion/no/such", "suite" => "scion" }, { "case_id" => M, "suite" => "scion" }]
    problems, = ratchet(run_passing(M), entries: recorded)

    assert_equal ["scion/no/such is recorded, and the corpus does not hold it",
                  "#{M} is recorded under suite scion; the corpus puts it in w3c"], problems
  end

  # sabotage: make run_problems skip the empty-results test; the
  # assert_equal on the refusal of a run of nothing fails.
  def test_refuses_a_run_of_nothing
    problems, = ratchet({})

    assert_equal ["no case was run: there is no run to ratchet from"], problems
  end
end
