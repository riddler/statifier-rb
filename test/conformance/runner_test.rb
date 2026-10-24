# frozen_string_literal: true

require "test_helper"
require_relative "copy_helper"
require_relative "registry"
require_relative "runner"

# The conformance runner: every case of every suite the vendored manifest
# lists, read with no skip list, each case's keys held to the set the copy's
# schema/case.json names. Every case is handed to the drive (the seam in
# test/conformance/runner.rb that the interpreter is plugged into); every
# case this package's registry claims must pass; and the run reports per
# suite how many cases are not yet claimed.
class RunnerTest < Minitest::Test
  include Conformance::CopyHelper

  CORPUS = Conformance::Corpus.load
  REGISTRY = JSON.parse(File.read(Conformance::Registry::PATH))

  def manifest_total = CORPUS.manifest["suites"].sum { |suite| suite["case_count"] }

  def load_error_after(relative, &)
    with_conformance_copy do |dir|
      rewrite_json(dir, relative, &)
      return assert_raises(Conformance::CorpusError) { Conformance::Corpus.load(dir) }.message
    end
  end

  # sabotage: make Corpus.load read only the first suite the manifest lists;
  # the assert_equal on the manifest's total case count fails.
  def test_reads_every_case_of_every_suite
    assert_equal(%w[scion w3c statifier], CORPUS.suites.map { |suite| suite["suite"] })
    assert_equal manifest_total, CORPUS.cases.size
    assert_equal CORPUS.cases.size, CORPUS.by_id.size
  end

  # sabotage: make Runner.run drop every failing result; the assert_equal on
  # the ids answered fails.
  def test_every_case_is_answered_pass_or_fail_with_no_skip
    results = Conformance::Runner.run(CORPUS)

    assert_equal CORPUS.cases.map { |item| item["id"] }, results.keys
    results.each_value do |result|
      assert_includes %w[pass fail], result["result"]
      refute_empty result["reason"] unless result["result"] == "pass"
    end
  end

  # sabotage: have Runner.run pass every case without calling the drive; the
  # assert_equal on the reason the drive gave fails.
  def test_every_case_is_handed_to_the_drive
    seen = []
    drive = ->(item) { (seen << item["id"]) && "drove #{item["id"]}" }
    results = Conformance::Runner.run(CORPUS, drive:)

    assert_equal CORPUS.cases.map { |item| item["id"] }, seen
    assert_equal "drove scion/actionSend/send1", results.fetch("scion/actionSend/send1")["reason"]
  end

  # sabotage: treat any truthy answer as a pass in Runner.result_for; the
  # assert_equal on the fail of a "true" answer fails.
  def test_only_pass_is_a_pass_and_a_raise_is_a_fail_naming_it
    answers = { "scion/actionSend/send1" => :pass, "scion/actionSend/send2" => "true" }
    drive = ->(item) { answers.fetch(item["id"]) { raise ArgumentError, "boom" } }
    results = Conformance::Runner.run(CORPUS, drive:)

    assert_equal({ "result" => "pass" }, results["scion/actionSend/send1"])
    assert_equal({ "result" => "fail", "reason" => "true" }, results["scion/actionSend/send2"])
    assert_equal({ "result" => "fail", "reason" => "raised ArgumentError: boom" }, results["w3c/test144"])
  end

  # sabotage: make Drive.call answer :pass; the assert_equal on the reason
  # every case fails with fails (and the registry would then claim cases no
  # driver drives).
  def test_the_drive_passes_nothing_while_no_driver_exists
    reasons = Conformance::Runner.run(CORPUS).values.map { |result| result["reason"] }.uniq

    assert_equal [Conformance::Drive::NOT_DRIVEN], reasons
  end

  # sabotage: have Runner.run answer {"result" => "fail"} for every case; the
  # assertion that each claimed case passes fails once the registry claims
  # one. With no entry it loops over nothing: the registry check
  # (rake registry) carries the same rule over a run made now.
  def test_every_claimed_case_passes
    results = Conformance::Runner.run(CORPUS)

    REGISTRY["entries"].each do |entry|
      assert_equal "pass", results.dig(entry["case_id"], "result"), "#{entry["case_id"]} is claimed and fails"
    end
  end

  # sabotage: make CaseShape#problems answer []; the assert_equal on the
  # refusal of the unknown top-level key fails (Corpus.load raises nothing).
  def test_a_case_carrying_a_key_the_schema_does_not_name_is_refused
    message = load_error_after("statifier/corpus/scion.json") { |file| file["cases"][0]["skip"] = true }

    assert_equal "case \"scion/actionSend/send1\" carries the key skip, which schema/case.json does not name", message
  end

  # sabotage: return [] from unknown_in_array in CaseShape; the assert_equal
  # on the refusal of the key inside a step's event fails.
  def test_a_key_the_schema_does_not_name_inside_a_step_is_refused
    message = load_error_after("statifier/corpus/scion.json") do |file|
      file["cases"][0]["steps"][0]["event"]["delay"] = 1
    end

    assert_equal "case \"scion/actionSend/send1\" carries the key steps[0].event.delay, " \
                 "which schema/case.json does not name", message
  end

  # sabotage: stop recursing into a known key's schema in
  # unknown_in_object; the assert_equal on the refusal of the key inside a
  # host's expected send fails.
  def test_a_key_the_schema_does_not_name_inside_a_host_object_is_refused
    message = load_error_after("statifier/corpus/statifier.json") do |file|
      file["cases"].find { |item| item.dig("host", "expect_sends", 0) }["host"]["expect_sends"][0]["extra"] = 1
    end

    assert_match(/carries the key host\.expect_sends\[0\]\.extra, which schema/, message)
  end

  # sabotage: drop the additionalProperties test in unknown_in_object (treat
  # every object with properties as closed); the assert_equal on the open
  # object's problems fails (its extra key is refused).
  def test_an_object_the_schema_leaves_open_takes_any_key
    schema = { "properties" => { "id" => {}, "a" => { "properties" => { "b" => {} } },
                                 "c" => { "properties" => { "d" => {} }, "additionalProperties" => false } },
               "additionalProperties" => false }
    shape = Conformance::CaseShape.new(schema)

    assert_equal [], shape.problems({ "id" => "x", "a" => { "b" => 1, "e" => 2 } })
    assert_equal ["case \"x\" carries the key c.e, which schema/case.json does not name"],
                 shape.problems({ "id" => "x", "c" => { "d" => 1, "e" => 2 } })
  end

  # sabotage: count the reference's entries in place of this package's in
  # unclaimed_lines; the assert_equal on the printed lines fails (no case is
  # then unclaimed).
  def test_reports_per_suite_the_cases_not_yet_claimed
    reference = Conformance::Records.reference_entries
    lines = Conformance::Runner.unclaimed_lines(CORPUS, REGISTRY["entries"], reference)
    puts lines

    assert_equal(%w[scion w3c statifier].map { |suite| expected_line(suite, reference) }, lines)
  end

  def expected_line(suite, reference)
    ours = REGISTRY["entries"].map { |entry| entry["case_id"] }
    open = CORPUS.cases_of(suite).map { |item| item["id"] } - ours
    theirs = reference.map { |entry| entry["case_id"] } & open
    "conformance: #{suite}: #{open.size} of #{CORPUS.cases_of(suite).size} cases not yet claimed " \
      "(the reference claims #{theirs.size} of them)"
  end
end
