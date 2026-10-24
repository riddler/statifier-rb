# frozen_string_literal: true

require "test_helper"
require_relative "registry"
require_relative "runner"

# The registry check (Conformance::RegistryCheck, the rake registry stage of
# the gate): every check the copy's RATCHET.md puts over a sibling's
# registry, against the corpus and the results of a run. The shipped
# registry passes and claims scion cases only; each other test hands the check a
# registry built here, never the committed file edited.
class RegistryTest < Minitest::Test
  CORPUS = Conformance::Corpus.load
  HASH = CORPUS.corpus_hash
  A = { "case_id" => "scion/actionSend/send1", "suite" => "scion" }.freeze
  B = { "case_id" => "scion/actionSend/send2", "suite" => "scion" }.freeze
  M = { "case_id" => "w3c/test144", "suite" => "w3c" }.freeze

  # A registry of A and M, as the reference encodes one.
  ENCODED = <<~JSON.freeze
    {
      "implementation": "statifier-rb",
      "corpus_hash": "#{HASH}",
      "claims": ["scion","w3c-mandatory"],
      "entries": [
        {"case_id":"scion/actionSend/send1","suite":"scion"},
        {"case_id":"w3c/test144","suite":"w3c"}
      ]
    }
  JSON

  def registry(entries, claims: Conformance::Registry.claims_of(entries, CORPUS.by_id), hash: HASH)
    Conformance::Registry.encode({ "implementation" => "statifier-rb", "corpus_hash" => hash,
                                   "claims" => claims, "entries" => entries })
  end

  # A run in which the cases named pass and every other case fails.
  def run_passing(*ids)
    drive = ->(item) { ids.include?(item["id"]) ? :pass : "not this one" }
    Conformance::Runner.run(CORPUS, drive:)
  end

  def problems(bytes, results = run_passing(A["case_id"], B["case_id"], M["case_id"]))
    Conformance::RegistryCheck.problems(bytes, CORPUS, results)
  end

  # sabotage: delete one entry line from conformance/registry.json; the
  # assert_equal on the registry's entry ids fails.
  def test_the_shipped_registry_holds_every_scion_case_and_claims_the_suite
    shipped = JSON.parse(File.read(Conformance::Registry::PATH))
    scion = CORPUS.cases_of("scion").map { |item| item["id"] }
    held = shipped["entries"].select { |entry| entry["suite"] == "scion" }

    assert_equal(scion, held.map { |entry| entry["case_id"] })
    assert_equal 119, held.size
    assert_includes shipped["claims"], "scion"
  end

  # sabotage: append a blank line to conformance/registry.json; the
  # assert_empty on its problems fails (the encoding check names it).
  def test_the_shipped_registry_passes_and_claims_the_suites_its_entries_count_toward
    bytes = File.binread(Conformance::Registry::PATH)
    shipped = JSON.parse(bytes)

    assert_empty Conformance::RegistryCheck.problems(bytes, CORPUS, Conformance::Runner.run(CORPUS))
    assert_equal %w[scion statifier w3c-mandatory w3c-optional], shipped["claims"]
    assert_equal %w[scion statifier w3c], shipped["entries"].map { |entry| entry["suite"] }.uniq
  end

  # sabotage: make currency answer []; the assert_equal on the entry that no
  # longer passes fails.
  def test_refuses_an_entry_that_no_longer_passes
    found = problems(registry([A, B]), run_passing(A["case_id"]))

    assert_equal ["the ratchet: scion/actionSend/send2 no longer passes: not this one"], found
  end

  # sabotage: compare the registry's corpus_hash with itself in pin; the
  # assert_equal on the pin problem fails.
  def test_refuses_a_pin_that_is_not_the_manifests_hash
    other = "sha256:#{"0" * 64}"

    assert_equal ["the pin: the registry's corpus_hash is #{other}; the vendored manifest's is #{HASH}"],
                 problems(registry([A], hash: other))
  end

  # sabotage: make order answer []; the assert_equal on the unsorted entries
  # fails.
  def test_refuses_an_unsorted_list
    assert_equal ["the order: scion/actionSend/send1 comes after scion/actionSend/send2; " \
                  "entries are sorted by suite, then case id"], problems(registry([B, A]))
  end

  # sabotage: compare the suite in Registry.entry_order only; the
  # assert_equal on a w3c entry written before a scion entry fails.
  def test_refuses_entries_out_of_suite_order
    found = problems(registry([M, A]))

    assert_equal ["the order: scion/actionSend/send1 comes after w3c/test144; " \
                  "entries are sorted by suite, then case id"], found
  end

  # sabotage: make membership answer []; the assert_equal on rule 1 fails.
  def test_refuses_an_entry_whose_case_the_corpus_does_not_hold_or_puts_in_another_suite
    found = problems(registry([{ "case_id" => "scion/no/such", "suite" => "scion" },
                               { "case_id" => "w3c/test144", "suite" => "scion" }], claims: ["scion"]))

    assert_equal ["rule 1: scion/no/such is in the registry but not in the corpus",
                  "rule 1: w3c/test144: the registry says suite scion, the corpus says w3c",
                  "the claims: claims is [\"scion\"]; the entries count toward [\"w3c-mandatory\"]"], found
  end

  # sabotage: make claims answer []; the assert_equal on the missing claim
  # fails.
  def test_refuses_claims_that_are_not_the_set_the_entries_count_toward
    assert_equal ["the claims: claims is [\"scion\"]; the entries count toward [\"scion\",\"w3c-mandatory\"]"],
                 problems(registry([A, M], claims: ["scion"]))
  end

  # sabotage: make duplicates answer []; the assert_includes on the twice
  # entered case fails.
  def test_refuses_a_case_entered_twice
    assert_includes problems(registry([A, A])), "scion/actionSend/send1 is entered more than once"
  end

  # sabotage: make encoding answer []; the assert_equal on the reflowed file
  # fails.
  def test_refuses_bytes_the_ratchet_would_not_write
    reflowed = JSON.pretty_generate(JSON.parse(registry([A])))

    assert_equal ["the registry's bytes are not what rake ratchet writes; something other than the ratchet wrote it"],
                 problems(reflowed)
  end

  # sabotage: make implementation answer []; the assert_equal on the name
  # fails.
  def test_refuses_another_implementations_name
    bytes = registry([A]).sub("statifier-rb", "statifier-ex")

    assert_equal ["the registry names the implementation \"statifier-ex\", not \"statifier-rb\""], problems(bytes)
  end

  # sabotage: make something answer []; the assert_equal on rule 3 fails.
  def test_refuses_a_check_over_a_run_of_nothing
    assert_equal ["the ratchet: scion/actionSend/send1 was not run today", "rule 3: no case was run"],
                 problems(registry([A]), {})
  end

  # sabotage: drop the keys test from Registry.parse; the assert_equal on the
  # refusal of a file without claims fails.
  def test_refuses_a_file_that_is_not_a_registry
    assert_equal(["the registry is not JSON"], problems("{").map { |line| line[/\A[^:]*/] })
    assert_equal ["the registry's keys are implementation, corpus_hash, entries; " \
                  "RATCHET.md's are implementation, corpus_hash, claims, entries"],
                 problems(JSON.generate({ "implementation" => "x", "corpus_hash" => HASH, "entries" => [] }))
  end

  # sabotage: write the entries on one line in Registry.encode; the
  # assert_equal on the encoded text fails.
  def test_encodes_one_entry_per_line_in_the_references_shape
    assert_equal ENCODED, registry([A, M])
  end
end
