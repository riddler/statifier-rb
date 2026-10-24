# frozen_string_literal: true

require_relative "registry"

module Conformance
  # The ratchet, the only writer of conformance/registry.json (rake ratchet;
  # rule 2 of the copy's RATCHET.md: the ratchet only moves forward).
  #
  # Its only input is the results of a run made now over the whole corpus;
  # there is no way to add a case by id, so every entry the file holds was
  # added by a run that observed the case pass. It never removes an entry: an
  # entry the run did not observe passing is a regression, and it refuses to
  # write, naming each one. Otherwise it writes the union of the recorded
  # entries and the passes, pinned to the vendored manifest's corpus_hash,
  # with exactly the claims those entries count toward. A run that passes
  # nothing new writes the same bytes again.
  module Ratchet
    # Writes the registry at path from results (Runner.run's over corpus).
    # Answers the problems that stopped it, having written nothing, or an
    # empty list once the file is written.
    def self.write(path, corpus, results)
      existing = Registry.parse(File.binread(path))
      return ["#{File.basename(path)}: #{existing}"] if existing.is_a?(String)

      registry = next_registry(existing, corpus, results)
      return registry if registry.is_a?(Array)

      File.binwrite(path, Registry.encode(registry))
      []
    end

    # The registry results earn from existing, or the problems that refuse it.
    def self.next_registry(existing, corpus, results)
      cases = corpus.by_id
      problems = run_problems(cases, results) + recorded_problems(existing["entries"], cases, results)
      return problems unless problems.empty?

      entries = merged(existing["entries"], cases, results)
      { "implementation" => IMPLEMENTATION, "corpus_hash" => corpus.corpus_hash,
        "claims" => Registry.claims_of(entries, cases), "entries" => entries }
    end

    # The recorded entries and the run's new passes, sorted.
    def self.merged(recorded, cases, results)
      ids = recorded.map { |entry| entry["case_id"] }
      passes = results.select { |_, result| result["result"] == "pass" }.keys
      added = (passes - ids).map { |id| { "case_id" => id, "suite" => cases[id]["suite"] } }
      (recorded + added).sort_by { |entry| Registry.entry_order(entry) }
    end

    # A run that is not of the whole corpus is no run to ratchet from.
    def self.run_problems(cases, results)
      return ["no case was run: there is no run to ratchet from"] if results.empty?
      return [] if results.keys.sort == cases.keys.sort

      ["the run is not of the whole corpus: #{results.size} results for #{cases.size} cases"]
    end

    # An entry already recorded must be the corpus's, under its suite, and
    # must have passed in this run; the answer otherwise is to fix the code,
    # never to drop the entry.
    def self.recorded_problems(entries, cases, results)
      entries.filter_map do |entry|
        id = entry["case_id"]
        next "#{id} is recorded, and the corpus does not hold it" unless cases.key?(id)
        next "#{id} is recorded under suite #{entry["suite"]}; the corpus puts it in #{cases[id]["suite"]}" \
          unless cases[id]["suite"] == entry["suite"]

        "#{id} is recorded and did not pass in this run" unless results.dig(id, "result") == "pass"
      end
    end

    private_class_method :merged, :run_problems, :recorded_problems
  end
end
