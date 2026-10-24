# frozen_string_literal: true

require "test_helper"
require_relative "registry"
require_relative "runner"

# What the shipped registry claims of the w3c suite, pinned against the
# corpus: a claim is the set of its entries (the copy's RATCHET.md,
# "Claims"), so each claim is held to exactly the cases it covers. The
# cases left out are named with the reason the run gives for each, so a
# case that starts to pass, or stops, shows up here and in the registry
# check together.
class W3cRegistryTest < Minitest::Test
  CORPUS = Conformance::Corpus.load
  REGISTRY = JSON.parse(File.read(Conformance::Registry::PATH))
  BASIC_HTTP = ["http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor"].freeze

  # The two mandatory cases the package does not pass yet; each leaves the
  # chart in the failing leaf at its initial configuration.
  MANDATORY_UNCLAIMED = %w[w3c/test330 w3c/test552].freeze

  # The optional cases that need no host processor.
  HOSTLESS_OPTIONAL = %w[w3c/test193 w3c/test278].freeze

  # The optional cases that need the Basic HTTP processor and pass through
  # the loopback front: every one but w3c/test201, which the reference
  # leaves unclaimed too.
  BASIC_HTTP_CLAIMED = %w[w3c/test509 w3c/test510 w3c/test518 w3c/test519 w3c/test520 w3c/test522 w3c/test531
                          w3c/test532 w3c/test534 w3c/test567 w3c/test577].freeze

  # The one case that needs the Basic HTTP processor and stays unclaimed.
  BASIC_HTTP_UNCLAIMED = "w3c/test201"

  def w3c = CORPUS.cases_of("w3c")

  def claimed_ids(claim)
    REGISTRY["entries"].select { |entry| Conformance::Records.claim_of(CORPUS.by_id.fetch(entry["case_id"])) == claim }
                       .map { |entry| entry["case_id"] }
  end

  def ids_where(&) = w3c.select(&).map { |item| item["id"] }

  # sabotage: remove "w3c-optional" from the registry's claims line; the
  # assert_equal on the claim names fails.
  def test_the_registry_makes_the_scion_statifier_and_both_w3c_claims
    assert_equal %w[scion statifier w3c-mandatory w3c-optional], REGISTRY["claims"]
    assert_equal REGISTRY["claims"], Conformance::Registry.claims_of(REGISTRY["entries"], CORPUS.by_id)
  end

  # sabotage: delete the w3c/test144 line from the registry; the
  # assert_equal on the mandatory entries fails (the case is missing).
  def test_w3c_mandatory_is_every_mandatory_case_but_the_two_that_fail
    mandatory = ids_where { _1["conformance"] == "mandatory" }

    assert_equal mandatory - MANDATORY_UNCLAIMED, claimed_ids("w3c-mandatory")
  end

  # sabotage: delete the w3c/test509 line from the registry; the
  # assert_equal on the optional entries fails (the case is missing).
  def test_w3c_optional_is_every_optional_case_but_test201
    assert_equal (HOSTLESS_OPTIONAL + BASIC_HTTP_CLAIMED).sort, claimed_ids("w3c-optional").sort
    hostless = ids_where { _1["conformance"] == "optional" && !_1.key?("host") }

    assert_equal HOSTLESS_OPTIONAL, hostless
    assert_equal [BASIC_HTTP_UNCLAIMED], ids_where { _1["conformance"] == "optional" } - claimed_ids("w3c-optional")
  end

  # sabotage: delete the scion/actionSend/send1 line from the registry; the
  # assert_equal on the scion entries fails (the case is missing).
  def test_scion_is_every_scion_case
    assert_equal CORPUS.cases_of("scion").map { _1["id"] }, claimed_ids("scion")
  end

  # sabotage: delete the statifier/send/registered_immediate line from the
  # registry; the assert_equal on the statifier entries fails (the case is
  # missing).
  def test_statifier_is_every_statifier_case_the_run_passes
    passing = CORPUS.cases_of("statifier").select { Conformance::Drive.call(_1) == :pass }.map { _1["id"] }

    assert_equal passing, claimed_ids("statifier")
    refute_empty passing
  end

  # sabotage: claim w3c/test201 in the registry; the assert_equal on the
  # claimed host-object cases fails.
  def test_every_case_that_needs_the_basic_http_processor_is_claimed_but_test201
    host = ids_where { _1.dig("host", "event_io_processors") == BASIC_HTTP }

    assert_equal [BASIC_HTTP_UNCLAIMED] + BASIC_HTTP_CLAIMED, host
    assert_equal BASIC_HTTP_CLAIMED, host & REGISTRY["entries"].map { _1["case_id"] }
    assert_equal(host, ids_where { _1.key?("host") })
  end

  # sabotage: drop the reported-miss handling from Calls#arrive (answer
  # `state` for every arrival); w3c/test509 then fails and the assert_equal
  # on the passing host cases fails.
  def test_the_basic_http_cases_pass_through_the_loopback_and_test201_fails_as_the_reference_does
    results = Conformance::Runner.run(CORPUS)

    assert_equal(BASIC_HTTP_CLAIMED, BASIC_HTTP_CLAIMED.select { results.fetch(_1)["result"] == "pass" })
    assert_equal 'the initial configuration: expected active leaf states ["pass"], got ["fail"]',
                 results.fetch(BASIC_HTTP_UNCLAIMED)["reason"]
    MANDATORY_UNCLAIMED.each { assert_equal "fail", results.fetch(_1)["result"] }
  end

  # The vendored reference registry, the reference's own at the tag the copy
  # names.
  REFERENCE = Conformance::Records.read(File.join(Conformance::ROOT, Conformance::VENDORED_DIR, "registry.json"))

  # sabotage: delete the w3c/test577 line from the registry; the
  # assert_equal on the entries fails.
  def test_the_registry_holds_the_reference_registry_entries_and_claims
    assert_equal REFERENCE["entries"], REGISTRY["entries"]
    assert_equal REFERENCE["claims"], REGISTRY["claims"]
    assert_equal REFERENCE["corpus_hash"], REGISTRY["corpus_hash"]
    assert_equal({ "scion" => 119, "statifier" => 36, "w3c" => 165 },
                 REGISTRY["entries"].map { _1["suite"] }.tally)
  end
end
