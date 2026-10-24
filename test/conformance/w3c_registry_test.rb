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
  OPTIONAL_CLAIMED = %w[w3c/test193 w3c/test278].freeze

  def w3c = CORPUS.cases_of("w3c")

  def claimed_ids(claim)
    REGISTRY["entries"].select { |entry| Conformance::Records.claim_of(CORPUS.by_id.fetch(entry["case_id"])) == claim }
                       .map { |entry| entry["case_id"] }
  end

  def ids_where(&) = w3c.select(&).map { |item| item["id"] }

  # sabotage: remove "w3c-optional" from the registry's claims line; the
  # assert_equal on the claim names fails.
  def test_the_registry_makes_the_scion_and_both_w3c_claims_and_not_the_statifier_one
    assert_equal %w[scion w3c-mandatory w3c-optional], REGISTRY["claims"]
    assert_equal REGISTRY["claims"], Conformance::Registry.claims_of(REGISTRY["entries"], CORPUS.by_id)
  end

  # sabotage: delete the w3c/test144 line from the registry; the
  # assert_equal on the mandatory entries fails (the case is missing).
  def test_w3c_mandatory_is_every_mandatory_case_but_the_two_that_fail
    mandatory = ids_where { _1["conformance"] == "mandatory" }

    assert_equal mandatory - MANDATORY_UNCLAIMED, claimed_ids("w3c-mandatory")
  end

  # sabotage: delete the w3c/test193 line from the registry; the
  # assert_equal on the optional entries fails (the case is missing).
  def test_w3c_optional_is_the_optional_cases_that_need_no_host_processor
    assert_equal OPTIONAL_CLAIMED, claimed_ids("w3c-optional")
    hostless = ids_where { _1["conformance"] == "optional" && !_1.key?("host") }

    assert_equal OPTIONAL_CLAIMED, hostless
  end

  # sabotage: delete the scion/actionSend/send1 line from the registry; the
  # assert_equal on the scion entries fails (the case is missing).
  def test_scion_is_every_scion_case_and_the_statifier_suite_has_no_entry
    assert_equal CORPUS.cases_of("scion").map { _1["id"] }, claimed_ids("scion")
    assert_empty claimed_ids("statifier")
  end

  # sabotage: claim w3c/test201 in the registry; the assert_equal on the
  # host-object cases fails (the registry then holds a case that needs
  # the BasicHTTP processor).
  def test_every_case_that_needs_the_basic_http_processor_stays_unclaimed
    host = ids_where { _1.dig("host", "event_io_processors") == BASIC_HTTP }

    assert_equal 12, host.size
    assert_empty host & REGISTRY["entries"].map { _1["case_id"] }
    with_host = ids_where { _1.key?("host") }

    assert_equal host, with_host
  end

  # sabotage: make Drive.unhonoured answer nil for a host object; the
  # assert_match on the reason fails (the case then runs and its outcome
  # differs).
  def test_a_host_case_fails_naming_the_processor_the_drive_has_none_of
    results = Conformance::Runner.run(CORPUS)

    assert_match(/host object \(event_io_processors\) is not honoured/, results.fetch("w3c/test201")["reason"])
    MANDATORY_UNCLAIMED.each { assert_equal "fail", results.fetch(_1)["result"] }
  end
end
