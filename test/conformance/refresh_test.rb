# frozen_string_literal: true

require "test_helper"
require_relative "refresh"

# The refresh (Conformance::Refresh, rake corpus:refresh), driven through its
# function against two throwaway git repositories made here: a stand-in for
# the reference, holding a small conformance/ at a tag, and a stand-in for
# this repository. Nothing here reads the real reference or writes the real
# copy.
class RefreshTest < Minitest::Test
  # Git run with no user configuration: no signing, no hooks, a fixed author.
  GIT = ["git", "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false",
         "-c", "tag.gpgsign=false", "-c", "core.hooksPath=/dev/null", "-c", "init.defaultBranch=main"].freeze

  def git(dir, *args)
    out, status = Open3.capture2e(*GIT, "-C", dir, *args)
    raise "git #{args.join(" ")}: #{out}" unless status.success?

    out
  end

  def write(dir, relative, text)
    path = File.join(dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, text)
  end

  # A reference repository whose conformance/ at tag v1.0.0 holds two suite
  # files, a manifest naming their hash (or hash, when given) and a readme.
  def reference(dir, hash: nil)
    suites = { "scion" => "{\"cases\":[1]}\n", "statifier" => "{\"cases\":[2]}\n" }
    suites.each { |suite, text| write(dir, "conformance/corpus/#{suite}.json", text) }
    hash ||= "sha256:#{Digest::SHA256.hexdigest(suites.values.join)}"
    write(dir, "conformance/manifest.json", "{\"corpus_hash\": \"#{hash}\"}\n")
    write(dir, "conformance/README.md", "a\n")
    git(dir, "init", "-q")
    git(dir, "add", "-A")
    git(dir, "commit", "-q", "-m", "a")
    git(dir, "tag", "v1.0.0")
    [git(dir, "rev-parse", "HEAD").strip, hash]
  end

  # A repository with a committed conformance/ holding only a readme.
  def repository(dir)
    write(dir, "conformance/README.md", "b\n")
    git(dir, "init", "-q")
    git(dir, "add", "-A")
    git(dir, "commit", "-q", "-m", "b")
  end

  # The line the recipe's printf writes for tag v1.0.0 at sha.
  def recipe_line(sha, hash)
    "{\"repo\":\"https://github.com/riddler/statifier-ex\",\"tag\":\"v1.0.0\",\"sha\":\"#{sha}\"," \
      "\"corpus_hash\":\"#{hash}\"}\n"
  end

  # Why a refresh of tag from from into repo refused.
  def refusal(from, repo, tag)
    assert_raises(Conformance::Refresh::Refused) { Conformance::Refresh.run(tag:, from:, repo_root: repo) }.message
  end

  def with_repositories
    Dir.mktmpdir("refresh") do |tmp|
      from = File.join(tmp, "reference")
      repo = File.join(tmp, "repository")
      repository(repo)
      yield(from, repo)
    end
  end

  # sabotage: write the provenance record without its trailing newline in
  # Refresh.record; the assert_equal on the record fails.
  def test_copies_every_file_at_the_tag_and_writes_the_record
    with_repositories do |from, repo|
      sha, hash = reference(from)
      line = Conformance::Refresh.run(tag: "v1.0.0", from:, repo_root: repo)

      assert_equal "corpus:refresh: 4 files from v1.0.0 (#{sha}) into conformance/statifier, #{hash}", line
      copy = File.join(repo, "conformance/statifier")

      assert_equal %w[README.md corpus/scion.json corpus/statifier.json manifest.json],
                   Dir.glob("**/*", base: copy).select { |path| File.file?(File.join(copy, path)) }.sort
      assert_equal recipe_line(sha, hash), File.binread(File.join(repo, "conformance/statifier.vendored.json"))
    end
  end

  # sabotage: make Refresh.dirty_paths answer []; the assert_raises on the
  # uncommitted record fails, and the copy is overwritten.
  def test_refuses_while_the_record_has_uncommitted_changes
    with_repositories do |from, repo|
      reference(from)
      write(repo, "conformance/statifier.vendored.json", "{}\n")

      message = refusal(from, repo, "v1.0.0")
      assert_equal "the copy or its record has uncommitted changes; commit or discard them first:\n" \
                   "?? conformance/statifier.vendored.json", message
      refute_path_exists File.join(repo, "conformance/statifier")
    end
  end

  # sabotage: list only the record in Refresh.dirty_paths; the assert_equal
  # on the edited copy's file fails.
  def test_refuses_while_the_copy_has_uncommitted_changes
    with_repositories do |from, repo|
      reference(from)
      Conformance::Refresh.run(tag: "v1.0.0", from:, repo_root: repo)
      git(repo, "add", "-A")
      git(repo, "commit", "-q", "-m", "c")
      write(repo, "conformance/statifier/README.md", "edited\n")

      assert_equal [" M conformance/statifier/README.md"], Conformance::Refresh.dirty_paths(repo)
    end
  end

  # sabotage: drop the refs/tags/ test in resolve_tag; the assert_raises on
  # the branch name fails (the branch resolves to a commit).
  def test_refuses_a_name_that_is_not_a_tag
    with_repositories do |from, repo|
      reference(from)

      message = refusal(from, repo, "main")
      assert_match(/\Amain is not a tag in /, message)
    end
  end

  # sabotage: drop the hash comparison in Refresh.stage; the assert_raises
  # on the copy whose manifest names another hash fails, and it is written.
  def test_refuses_a_copy_that_does_not_hash_to_its_manifest_and_writes_nothing
    with_repositories do |from, repo|
      other = "sha256:#{"0" * 64}"
      reference(from, hash: other)

      message = refusal(from, repo, "v1.0.0")
      assert_match(/\Athe copy at v1\.0\.0 hashes to "sha256:[0-9a-f]{64}"; its manifest says #{other}\z/, message)
      refute_path_exists File.join(repo, "conformance/statifier")
      refute_path_exists File.join(repo, "conformance/statifier.vendored.json")
    end
  end
end
