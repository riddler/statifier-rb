# frozen_string_literal: true

require "digest"
require "json"

# The conformance apparatus: the corpus vendored under conformance/, the run
# over it, the corpus check, the registry, the ratchet and the refresh. It
# lives under test/ because it is not part of the gem: the gemspec ships lib/
# alone, and nothing in lib/ knows the corpus exists. The Rakefile loads these
# files for its corpus:check, corpus:refresh, registry and ratchet tasks, and
# the suite loads them for its tests.
#
# The contract is the reference's, read in the copy at the tag the provenance
# record names: conformance/statifier/README.md (what each file is) and
# conformance/statifier/RATCHET.md (the registry, its checks and the vendoring
# recipe). conformance/README.md says what is copied and what is this
# repository's own.
module Conformance
  # This repository's conformance directory.
  ROOT = File.expand_path("../../conformance", __dir__)

  # Where the copy lands under ROOT: the recipe's DEST, conformance/statifier.
  VENDORED_DIR = "statifier"

  # The provenance record, beside the copy: the recipe's "$DEST.vendored.json".
  PROVENANCE_FILE = "statifier.vendored.json"

  # This package's registry, outside the copy.
  REGISTRY_FILE = "registry.json"

  # The repository the copy is taken from, as the recipe records it.
  REFERENCE_REPO = "https://github.com/riddler/statifier-ex"

  # This package's name in its own registry.
  IMPLEMENTATION = "statifier-rb"

  # The suites, in the order the corpus hash concatenates their files.
  SUITES = %w[scion w3c statifier].freeze

  # The four claim names, sorted.
  CLAIMS = %w[scion statifier w3c-mandatory w3c-optional].freeze

  # A corpus that does not read: a suite file that is not JSON or holds no
  # list of cases, or a case carrying a key the case schema does not name.
  class CorpusError < StandardError; end

  # Reading the files the apparatus holds to one another.
  module Records
    # The parsed JSON at path.
    def self.read(path) = JSON.parse(File.read(path))

    # The corpus hash recomputed from the copy under root, as the recipe
    # computes it: `sha256:` and the hex SHA-256 of the bytes of
    # corpus/<suite>.json concatenated in suite order (scion, w3c,
    # statifier), skipping a suite with no file. nil when no corpus file
    # exists, which every caller treats as a failure.
    def self.corpus_hash(root = ROOT)
      files = SUITES.map { |suite| File.join(root, VENDORED_DIR, "corpus", "#{suite}.json") }.select { File.file?(_1) }
      return if files.empty?

      digest = Digest::SHA256.new
      files.each { |path| digest << File.binread(path) }
      "sha256:#{digest.hexdigest}"
    end

    # The vendored reference registry's entries: the reference's claim,
    # never this package's.
    def self.reference_entries(root = ROOT) = read(File.join(root, VENDORED_DIR, "registry.json")).fetch("entries")

    # The claim a case counts toward: its suite, with the w3c suite split by
    # the case's conformance class; nil for a w3c case with no class.
    def self.claim_of(item)
      return item["suite"] unless item["suite"] == "w3c"

      "w3c-#{item["conformance"]}" if %w[mandatory optional].include?(item["conformance"])
    end
  end

  # The keys a case may carry, read out of the vendored schema/case.json
  # rather than written here: at every object the schema closes
  # (`additionalProperties: false`), the keys its `properties` names, and
  # below each, the keys of the schema it names for that key, through arrays
  # by their `items`. A key outside that set, at any depth the schema closes,
  # is refused rather than half-read, so a corpus that grows a key is noticed
  # here the day it is vendored.
  class CaseShape
    def initialize(schema)
      @schema = schema
    end

    # One sentence per key of item the schema does not name; empty when none.
    def problems(item)
      unknown(item, @schema, nil).map do |path|
        "case #{item["id"].inspect} carries the key #{path}, which schema/case.json does not name"
      end
    end

    private

    def unknown(value, schema, path)
      case value
      when Hash then unknown_in_object(value, schema, path)
      when Array then unknown_in_array(value, schema["items"], path)
      else []
      end
    end

    def unknown_in_array(values, items, path)
      return [] unless items.is_a?(Hash)

      values.each_with_index.flat_map { |value, index| unknown(value, items, "#{path}[#{index}]") }
    end

    def unknown_in_object(object, schema, path)
      properties = schema["properties"]
      return [] unless properties.is_a?(Hash)

      object.flat_map do |key, value|
        at = path ? "#{path}.#{key}" : key
        next unknown(value, properties[key], at) if properties.key?(key)

        schema["additionalProperties"] == false ? [at] : []
      end
    end
  end

  # The vendored corpus: its manifest and every case of every suite the
  # manifest lists, in the manifest's order.
  Corpus = Data.define(:manifest, :suites) do
    # Reads the corpus under root, refusing (CorpusError) a suite file that
    # does not read and a case carrying a key the case schema does not name.
    def self.load(root = ROOT)
      dir = File.join(root, VENDORED_DIR)
      manifest = Records.read(File.join(dir, "manifest.json"))
      shape = CaseShape.new(Records.read(File.join(dir, "schema", "case.json")))
      suites = manifest.fetch("suites").map { |entry| read_suite(dir, entry, shape) }
      new(manifest:, suites:)
    end

    def self.read_suite(dir, entry, shape)
      cases = read_cases(File.join(dir, entry.fetch("file")), entry["file"])
      problems = cases.flat_map { |item| shape.problems(item) }
      raise CorpusError, problems.join("; ") unless problems.empty?

      { "suite" => entry.fetch("suite"), "file" => entry["file"], "cases" => cases }
    end

    def self.read_cases(path, name)
      cases = JSON.parse(File.read(path))["cases"]
      raise CorpusError, "#{name} holds no list of cases" unless cases.is_a?(Array)

      cases
    rescue JSON::ParserError => e
      raise CorpusError, "#{name} is not JSON: #{e.message}"
    end

    private_class_method :read_suite, :read_cases

    def corpus_hash = manifest.fetch("corpus_hash")

    # Every case of every suite, in the manifest's suite order.
    def cases = suites.flat_map { |suite| suite["cases"] }

    # The cases of the named suite; none for a suite the corpus lacks.
    def cases_of(name) = suites.find { |suite| suite["suite"] == name }&.fetch("cases") || []

    # The id => case map.
    def by_id = cases.to_h { |item| [item.fetch("id"), item] }
  end
end
