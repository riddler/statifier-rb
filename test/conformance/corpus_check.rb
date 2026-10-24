# frozen_string_literal: true

require_relative "corpus"

module Conformance
  # The corpus check, a stage of the gate (rake corpus:check): it recomputes
  # the corpus hash from the copy as the reference's vendoring recipe does and
  # requires it to equal each of four fields:
  #
  # 1. the vendored manifest's corpus_hash;
  # 2. the provenance record's corpus_hash, beside the copy;
  # 3. this package's registry's corpus_hash, outside the copy;
  # 4. the vendored reference registry's corpus_hash, inside the copy.
  #
  # It also holds the manifest's list of suites to the suite files it names,
  # each present with the case count the manifest gives.
  #
  # A mismatch names the field that disagrees. It is never repaired by
  # rewriting a hash: the hash is what a claim of conformance is pinned to,
  # and a hash rewritten to match whatever is on disk pins it to nothing. The
  # fix is to restore the copied bytes, or to refresh the copy to a tag
  # (conformance/README.md).
  module CorpusCheck
    # The four fields, each as its label and its path under the conformance
    # root.
    FIELDS = [
      ["the vendored manifest's corpus_hash", File.join(VENDORED_DIR, "manifest.json")],
      ["the provenance record's corpus_hash", PROVENANCE_FILE],
      ["this package's registry's corpus_hash", REGISTRY_FILE],
      ["the vendored reference registry's corpus_hash", File.join(VENDORED_DIR, "registry.json")]
    ].freeze

    # Every disagreement under root, one sentence each; empty when the copy
    # hashes to what all four fields say and the manifest's suites are there.
    def self.problems(root = ROOT)
      computed = Records.corpus_hash(root)
      return ["there is no corpus file under #{VENDORED_DIR}/corpus: nothing to hash"] if computed.nil?

      FIELDS.filter_map { |label, path| field_problem(root, label, path, computed) } + suite_problems(root)
    end

    # The line the task prints when there is nothing to report.
    def self.summary(root = ROOT)
      record = Records.read(File.join(root, PROVENANCE_FILE))
      counts = manifest_suites(root).map { |entry| "#{entry["suite"]} #{entry["case_count"]}" }.join(", ")
      "corpus:check: #{record["repo"]} at #{record["tag"]} (#{record["sha"]}), #{counts} cases; " \
        "the copy hashes to #{record["corpus_hash"]}, as all four fields say"
    end

    def self.field_problem(root, label, path, computed)
      value = read_field(File.join(root, path))
      return "#{label} cannot be read: #{value[:error]}" if value.is_a?(Hash)
      return if value == computed

      "#{label} is #{value.inspect}; the suite files hash to #{computed}"
    end

    def self.read_field(path)
      return { error: "#{File.basename(path)} is missing" } unless File.file?(path)

      Records.read(path)["corpus_hash"]
    rescue JSON::ParserError => e
      { error: "it is not JSON (#{e.message})" }
    end

    def self.suite_problems(root)
      manifest_suites(root).filter_map do |entry|
        path = File.join(root, VENDORED_DIR, entry["file"])
        next "the manifest lists #{entry["file"]}, which the copy lacks" unless File.file?(path)

        count = Records.read(path)["cases"]&.size
        next if count == entry["case_count"]

        "#{entry["file"]} holds #{count.inspect} cases; the manifest says #{entry["case_count"]}"
      rescue JSON::ParserError => e
        "#{entry["file"]} is not JSON: #{e.message}"
      end
    end

    # The manifest's suites; none when the manifest does not read, which the
    # first field has already named.
    def self.manifest_suites(root)
      Records.read(File.join(root, VENDORED_DIR, "manifest.json")).fetch("suites", [])
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    private_class_method :field_problem, :read_field, :suite_problems, :manifest_suites
  end
end
