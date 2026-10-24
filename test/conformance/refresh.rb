# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require_relative "corpus"

module Conformance
  # The refresh (rake corpus:refresh): moves the copy to a statifier-ex tag by
  # the sequence under "Vendoring the corpus" in the copy's RATCHET.md, with
  # DEST set to conformance/statifier. Every file under conformance/ at the
  # tag is written through `git show` as git stores it, with no edit of any
  # kind; the copy's corpus hash is recomputed and required to equal its
  # manifest's; and the provenance record {repo, tag, sha, corpus_hash} is
  # written as one line beside the copy. Nothing is written until the copy
  # has hashed to its manifest's hash.
  #
  # It reads the tag from a clone of the reference (any git directory that
  # holds the tag, bare or not); the record names the public repository,
  # never the clone's path. A refresh is a reviewed change, never a silent
  # update: it refuses while the copy or the provenance record has
  # uncommitted changes, so it never overwrites work that is not in git. No
  # gate stage and no test runs it against this repository's copy.
  module Refresh
    # A refresh that did not happen, and why.
    class Refused < StandardError; end

    # Moves the copy under repo_root's conformance/ to tag, read from the git
    # directory from. Answers the line the task prints; raises Refused,
    # having written nothing, when it may not or cannot.
    def self.run(tag:, from:, repo_root:)
      refuse_dirty(repo_root)
      sha = resolve_tag(from, tag)
      Dir.mktmpdir("statifier-corpus") do |scratch|
        count, hash = stage(from, sha, tag, scratch)
        install(scratch, File.join(repo_root, "conformance"), record(tag, sha, hash))
        "corpus:refresh: #{count} files from #{tag} (#{sha}) into conformance/#{VENDORED_DIR}, #{hash}"
      end
    end

    # The provenance record's line, as the recipe's printf writes it.
    def self.record(tag, sha, corpus_hash)
      "#{JSON.generate({ "repo" => REFERENCE_REPO, "tag" => tag, "sha" => sha, "corpus_hash" => corpus_hash })}\n"
    end

    # The uncommitted changes git reports under repo_root to the copy and the
    # record, untracked files included.
    def self.dirty_paths(repo_root)
      paths = [File.join("conformance", VENDORED_DIR), File.join("conformance", PROVENANCE_FILE)]
      git(repo_root, "status", "--porcelain", "--untracked-files=all", "--", *paths).lines.map(&:chomp)
    end

    def self.refuse_dirty(repo_root)
      dirty = dirty_paths(repo_root)
      return if dirty.empty?

      raise Refused, "the copy or its record has uncommitted changes; commit or discard them first:\n" \
                     "#{dirty.join("\n")}"
    end

    def self.resolve_tag(from, tag)
      _, status = Open3.capture2e("git", "-C", from, "rev-parse", "-q", "--verify", "refs/tags/#{tag}")
      raise Refused, "#{tag} is not a tag in #{from}; a tag is what is recorded, never a branch" unless status.success?

      git(from, "rev-parse", "#{tag}^{commit}").strip
    end

    # Writes the copy at sha into scratch/statifier and answers its file
    # count and corpus hash, refusing a copy that does not hash to its
    # manifest's.
    def self.stage(from, sha, tag, scratch)
      paths = git(from, "ls-tree", "-r", "--name-only", sha, "--", "conformance/").lines.map(&:chomp)
      raise Refused, "there is no conformance/ at #{tag} (#{sha})" if paths.empty?

      paths.each { |path| write_blob(from, sha, path, File.join(scratch, VENDORED_DIR)) }
      [paths.size, staged_hash(scratch, tag)]
    end

    # The staged copy's corpus hash, refused unless it is its manifest's.
    def self.staged_hash(scratch, tag)
      hash = Records.corpus_hash(scratch)
      wanted = Records.read(File.join(scratch, VENDORED_DIR, "manifest.json"))["corpus_hash"]
      raise Refused, "the copy at #{tag} hashes to #{hash.inspect}; its manifest says #{wanted}" unless hash == wanted

      hash
    end

    def self.write_blob(from, sha, path, copy)
      out = File.join(copy, path.delete_prefix("conformance/"))
      FileUtils.mkdir_p(File.dirname(out))
      File.binwrite(out, git(from, "show", "#{sha}:#{path}"))
    end

    def self.install(scratch, conformance, line)
      dest = File.join(conformance, VENDORED_DIR)
      FileUtils.rm_rf(dest)
      FileUtils.mkdir_p(conformance)
      FileUtils.cp_r(File.join(scratch, VENDORED_DIR), dest)
      File.binwrite(File.join(conformance, PROVENANCE_FILE), line)
    end

    # The output of git, run in dir, read as bytes; raises Refused when git
    # fails.
    def self.git(dir, *args)
      out, err, status = Open3.capture3("git", "-C", dir, *args, binmode: true)
      raise Refused, "git #{args.first} failed in #{dir}: #{err.strip}" unless status.success?

      out
    end

    private_class_method :refuse_dirty, :resolve_tag, :staged_hash, :stage, :write_blob, :install, :git
  end
end
