# frozen_string_literal: true

require "test_helper"
require_relative "corpus_check"
require_relative "copy_helper"

# The corpus check (Conformance::CorpusCheck, the rake corpus:check stage of
# the gate): the copy hashes to what the vendored manifest, the provenance
# record, this package's registry and the vendored reference registry say.
# The shipped files pass; each other test breaks one thing in a throwaway
# copy and asserts the check names the field that disagrees.
class CorpusCheckTest < Minitest::Test
  include Conformance::CopyHelper

  HASH = "sha256:7440f9a34a84b0657cb3bde11f96cf1707db08fb05e202c1e0249ab965517cc8"
  OTHER = "sha256:#{"0" * 64}".freeze

  def problems_after(relative, &)
    with_conformance_copy do |dir|
      rewrite(dir, relative, &)
      return Conformance::CorpusCheck.problems(dir)
    end
  end

  # sabotage: append a space to conformance/statifier/corpus/statifier.json;
  # the assert_empty on the shipped files' problems fails.
  def test_the_shipped_copy_hashes_to_all_four_fields
    assert_empty Conformance::CorpusCheck.problems
    assert_equal HASH, Conformance::Records.corpus_hash
  end

  # sabotage: hash the suite files in the order statifier, w3c, scion in
  # Records.corpus_hash; the assert_equal on the recomputed hash fails.
  def test_the_hash_is_over_the_suite_files_in_suite_order
    dir = File.join(Conformance::ROOT, "statifier", "corpus")
    bytes = %w[scion w3c statifier].map { |suite| File.binread(File.join(dir, "#{suite}.json")) }.join

    assert_equal "sha256:#{Digest::SHA256.hexdigest(bytes)}", Conformance::Records.corpus_hash
  end

  # sabotage: drop the provenance record's row from CorpusCheck::FIELDS; the
  # assert_equal on the four named fields fails (three are named).
  def test_a_changed_suite_byte_fails_every_field_naming_each
    problems = problems_after("statifier/corpus/w3c.json") { |bytes| bytes.sub("w3c/test", "w3c/tesT") }

    assert_equal(["the vendored manifest's corpus_hash", "the provenance record's corpus_hash",
                  "this package's registry's corpus_hash", "the vendored reference registry's corpus_hash"],
                 problems.map { |line| line[/\A.*?corpus_hash/] })
    assert(problems.all? { |line| line.include?("is #{HASH.inspect}; the suite files hash to sha256:") })
  end

  # sabotage: compare each field with the manifest's corpus_hash rather than
  # the recomputed one in field_problem; the assert_equal on the problem
  # naming the provenance record fails (the copy still agrees with the
  # manifest, so nothing is named).
  def test_a_rewritten_provenance_hash_fails_naming_the_record
    problems = problems_after("statifier.vendored.json") { |bytes| bytes.sub(HASH, OTHER) }

    assert_equal ["the provenance record's corpus_hash is #{OTHER.inspect}; the suite files hash to #{HASH}"], problems
  end

  # sabotage: drop the registry's row from CorpusCheck::FIELDS; the
  # assert_equal on the problem naming this package's registry fails.
  def test_a_registry_pinned_to_another_corpus_fails_naming_it
    problems = problems_after("registry.json") { |bytes| bytes.sub(HASH, OTHER) }

    assert_equal ["this package's registry's corpus_hash is #{OTHER.inspect}; the suite files hash to #{HASH}"],
                 problems
  end

  # sabotage: drop the vendored reference registry's row from
  # CorpusCheck::FIELDS; the assert_equal on the problem naming it fails.
  def test_a_reference_registry_out_of_step_fails_naming_it
    problems = problems_after("statifier/registry.json") { |bytes| bytes.sub(HASH, OTHER) }

    assert_equal ["the vendored reference registry's corpus_hash is #{OTHER.inspect}; " \
                  "the suite files hash to #{HASH}"], problems
  end

  # sabotage: make read_field answer the hash whatever the file; the
  # assert_includes on the missing record fails.
  def test_a_missing_record_is_named
    with_conformance_copy do |dir|
      File.delete(File.join(dir, "statifier.vendored.json"))

      assert_includes Conformance::CorpusCheck.problems(dir),
                      "the provenance record's corpus_hash cannot be read: statifier.vendored.json is missing"
    end
  end

  # sabotage: make suite_problems answer []; the assert_includes on the
  # case count fails.
  def test_a_suite_file_whose_cases_disagree_with_its_case_count_is_named
    with_conformance_copy do |dir|
      rewrite_json(dir, "statifier/manifest.json") { |manifest| manifest["suites"][0]["case_count"] = 120 }

      assert_includes Conformance::CorpusCheck.problems(dir),
                      "corpus/scion.json holds 119 cases; the manifest says 120"
    end
  end

  # sabotage: skip the File.file? test in suite_problems; the assertion on
  # the missing suite file fails (the check raises instead).
  def test_a_listed_suite_file_the_copy_lacks_is_named
    with_conformance_copy do |dir|
      File.delete(File.join(dir, "statifier", "corpus", "statifier.json"))

      assert_includes Conformance::CorpusCheck.problems(dir),
                      "the manifest lists corpus/statifier.json, which the copy lacks"
    end
  end

  # sabotage: make Records.corpus_hash hash an empty list of files; the
  # assert_equal on the one problem saying there is nothing to hash fails.
  def test_no_corpus_file_at_all_is_a_failure
    with_conformance_copy do |dir|
      FileUtils.rm_rf(File.join(dir, "statifier", "corpus"))

      assert_equal ["there is no corpus file under statifier/corpus: nothing to hash"],
                   Conformance::CorpusCheck.problems(dir)
    end
  end

  # sabotage: drop the record's sha from the summary line; the
  # assert_includes on the tag and the commit fails.
  def test_the_summary_names_the_tag_and_the_commit
    summary = Conformance::CorpusCheck.summary

    assert_includes summary, "at v2.16.0 (76742af12138887c7f95125a80edf2b0a7dbaaf3)"
    assert_includes summary, "scion 119, w3c 168, statifier 36 cases"
  end
end
