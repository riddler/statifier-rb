# frozen_string_literal: true

require "test_helper"
require_relative "refresh"

# The vendored copy and its provenance record, beside what the corpus check
# holds: the record is the one line the recipe writes, the copy carries the
# reference's own files and the licences, and none of conformance/ ships in
# the gem.
class VendoredTest < Minitest::Test
  ROOT = Conformance::ROOT
  RECORD = File.binread(File.join(ROOT, "statifier.vendored.json"))

  # sabotage: reorder the keys in Refresh.record (tag first); the
  # assert_equal on the committed record's line fails.
  def test_the_record_is_the_one_line_the_recipe_writes
    record = JSON.parse(RECORD)

    assert_equal %w[repo tag sha corpus_hash], record.keys
    assert_equal Conformance::Refresh.record(record["tag"], record["sha"], record["corpus_hash"]), RECORD
    assert_match(/\A[0-9a-f]{40}\z/, record["sha"])
    assert_equal "https://github.com/riddler/statifier-ex", record["repo"]
  end

  # sabotage: delete conformance/statifier/LICENSES/Apache-2.0.txt from the
  # copy; the assertion that each named file exists fails.
  def test_the_copy_carries_the_references_files_and_the_licences
    %w[README.md RATCHET.md registry.json exclusions.json manifest.json schema/case.json schema/registry.json
       LICENSES/Apache-2.0.txt LICENSES/BSD-3-Clause-W3C.txt].each do |path|
      assert_path_exists File.join(ROOT, "statifier", path)
    end
    refute_empty Dir.glob("cases/**/*.json", base: File.join(ROOT, "statifier"))
  end

  # sabotage: add "conformance/**/*" to the gemspec's files; the assertion
  # that no packaged file is under conformance/ fails.
  def test_the_gem_ships_none_of_conformance
    files = Gem::Specification.load(File.expand_path("../../statifier.gemspec", __dir__)).files

    refute_empty files
    assert(files.none? { |path| path.start_with?("conformance/") }, "the gemspec packages conformance/")
  end
end
