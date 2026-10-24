# frozen_string_literal: true

require "json"
require_relative "corpus"

module Conformance
  # The file conformance/registry.json: the corpus cases this package claims
  # to pass, against the pinned corpus. Its contract is the copy's RATCHET.md:
  # the four fields, claims sorted, entries sorted by suite then case id, one
  # entry per line, written only by a run that observed the pass (Ratchet),
  # and the checks a sibling's registry check runs (RegistryCheck).
  module Registry
    # The registry this repository ships.
    PATH = File.join(ROOT, REGISTRY_FILE)

    # The top-level keys, in the order RATCHET.md's table gives them and the
    # encoding writes them.
    KEYS = %w[implementation corpus_hash claims entries].freeze

    # The order RATCHET.md gives entries: by suite, then by case id (String
    # comparison in Ruby is by byte, which for UTF-8 is codepoint order).
    def self.entry_order(entry) = [entry["suite"], entry["case_id"]]

    # The registry's bytes, in the reference's encoding: the four keys in
    # order, claims on one line, each entry one line of compact JSON. Entries
    # are written in the order given; a registry with none writes `[]`.
    def self.encode(registry)
      entries = registry.fetch("entries").map do |entry|
        "    #{JSON.generate({ "case_id" => entry.fetch("case_id"), "suite" => entry.fetch("suite") })}"
      end
      list = entries.empty? ? "[]" : "[\n#{entries.join(",\n")}\n  ]"
      head = KEYS.take(3).map { |key| "  #{JSON.generate(key)}: #{JSON.generate(registry.fetch(key))}," }
      ["{", *head, "  \"entries\": #{list}", "}", ""].join("\n")
    end

    # The parsed registry, or a sentence saying why bytes are not one.
    def self.parse(bytes)
      registry = JSON.parse(bytes)
      return "the registry is not a JSON object" unless registry.is_a?(Hash)
      return "the registry's keys are #{registry.keys.join(", ")}; RATCHET.md's are #{KEYS.join(", ")}" \
        unless registry.keys.sort == KEYS.sort
      return "the registry's claims and entries must be arrays" \
        unless registry["claims"].is_a?(Array) && registry["entries"].is_a?(Array)

      registry
    rescue JSON::ParserError => e
      "the registry is not JSON: #{e.message}"
    end

    # The sorted set of claim names entries count toward, their cases read
    # in cases (an id => case map). An entry the corpus lacks counts toward
    # nothing here; rule 1 is where it fails.
    def self.claims_of(entries, cases)
      entries.filter_map { |entry| cases[entry["case_id"]] && Records.claim_of(cases[entry["case_id"]]) }.uniq.sort
    end
  end

  # Every check the copy's RATCHET.md puts over a sibling's registry ("The
  # check"), run over the file's bytes against the corpus and the results of
  # a run made now: the pin, rule 1, the claims, every entry passing today
  # and something to check; and besides them the implementation name, the
  # order, one entry per case and the encoding, so the file is the one the
  # ratchet would write.
  #
  # Before its first entry the registry carries the pin, no claims and no
  # entries. The reference's schema/registry.json refuses that file (an empty
  # registry is a defect, not a claim); here it passes the check as the
  # registry that makes no claim, which the task says rather than reporting
  # a pass of anything.
  class RegistryCheck
    CHECKS = %i[implementation pin order duplicates membership claims encoding currency something].freeze

    # One sentence per problem with the registry in bytes, against corpus and
    # results (Runner.run's); empty when it passes.
    def self.problems(bytes, corpus, results)
      registry = Registry.parse(bytes)
      return [registry] if registry.is_a?(String)

      check = new(registry, bytes, corpus, results)
      CHECKS.flat_map { |name| check.send(name) }
    end

    def initialize(registry, bytes, corpus, results)
      @registry = registry
      @bytes = bytes
      @corpus = corpus
      @results = results
      @cases = corpus.by_id
    end

    private

    attr_reader :registry, :corpus, :results, :cases

    def entries = registry["entries"]

    def implementation
      return [] if registry["implementation"] == IMPLEMENTATION

      ["the registry names the implementation #{registry["implementation"].inspect}, not #{IMPLEMENTATION.inspect}"]
    end

    def pin
      return [] if registry["corpus_hash"] == corpus.corpus_hash

      ["the pin: the registry's corpus_hash is #{registry["corpus_hash"]}; " \
       "the vendored manifest's is #{corpus.corpus_hash}"]
    end

    def order
      entries.each_cons(2).filter_map do |left, right|
        next if (Registry.entry_order(left) <=> Registry.entry_order(right)).to_i <= 0

        "the order: #{right["case_id"]} comes after #{left["case_id"]}; entries are sorted by suite, then case id"
      end
    end

    def duplicates
      entries.map { |entry| entry["case_id"] }.tally.select { |_, count| count > 1 }
             .map { |id, _| "#{id} is entered more than once" }
    end

    def membership
      entries.filter_map do |entry|
        item = cases[entry["case_id"]]
        next "rule 1: #{entry["case_id"]} is in the registry but not in the corpus" if item.nil?
        next if item["suite"] == entry["suite"]

        "rule 1: #{entry["case_id"]}: the registry says suite #{entry["suite"]}, the corpus says #{item["suite"]}"
      end
    end

    def claims
      wanted = Registry.claims_of(entries, cases)
      return [] if registry["claims"] == wanted

      ["the claims: claims is #{JSON.generate(registry["claims"])}; the entries count toward #{JSON.generate(wanted)}"]
    end

    def encoding
      return [] if Registry.encode(registry) == @bytes

      ["the registry's bytes are not what rake ratchet writes; something other than the ratchet wrote it"]
    end

    def currency
      entries.filter_map do |entry|
        result = results[entry["case_id"]]
        next if result.nil? && cases[entry["case_id"]].nil?
        next "the ratchet: #{entry["case_id"]} was not run today" if result.nil?
        next if result["result"] == "pass"

        "the ratchet: #{entry["case_id"]} no longer passes: #{result["reason"]}"
      end
    end

    def something
      problems = []
      problems << "rule 3: there is no corpus case to read" if cases.empty?
      problems << "rule 3: no case was run" if results.empty?
      problems
    end
  end
end
