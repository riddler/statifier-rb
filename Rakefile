# frozen_string_literal: true

require "minitest/test_task"
require "rubocop/rake_task"
require_relative "test/conformance/corpus_check"
require_relative "test/conformance/ratchet"
require_relative "test/conformance/refresh"
require_relative "test/conformance/registry"
require_relative "test/conformance/runner"

RuboCop::RakeTask.new

# The suite runs under SimpleCov (configured in .simplecov), which fails the
# run below the coverage minimum. SimpleCov is required in the prelude, ahead
# of minitest/autorun, so that it reports after the suite has run rather than
# before it.
Minitest::TestTask.create(:test) do |t|
  t.test_prelude = %(require "simplecov")
  t.test_globs = ["test/**/*_test.rb"]
end

# The conformance apparatus under conformance/ (its README says what is
# copied, from where, and what is this repository's own). The code these
# tasks call lives in test/conformance/, beside the suite that tests it;
# none of it ships.
namespace :corpus do
  desc "Check that the vendored corpus hashes to what its four records say"
  task :check do
    problems = Conformance::CorpusCheck.problems
    unless problems.empty?
      abort ["corpus:check failed:", *problems,
             "Restore the copied bytes or refresh the copy to a tag; never rewrite a hash."].join("\n  ")
    end
    puts Conformance::CorpusCheck.summary
  end

  desc "Move conformance/statifier/ to a statifier-ex tag, read from a clone: rake \"corpus:refresh[TAG,CLONE]\""
  task :refresh, %i[tag from] do |_task, args|
    abort "corpus:refresh: name the tag and a clone of statifier-ex: rake \"corpus:refresh[TAG,CLONE]\"" \
      unless args[:tag] && args[:from]

    puts Conformance::Refresh.run(tag: args[:tag], from: File.expand_path(args[:from]), repo_root: __dir__)
  rescue Conformance::Refresh::Refused => e
    abort "corpus:refresh refused; nothing was written: #{e.message}"
  end
end

# A stage of the gate: every check the copy's RATCHET.md puts over a
# sibling's registry, against a run of the whole corpus made now.
desc "Check conformance/registry.json against the corpus and a run made now"
task :registry do
  corpus = Conformance::Corpus.load
  bytes = File.binread(Conformance::Registry::PATH)
  results = Conformance::Runner.run(corpus)
  problems = Conformance::RegistryCheck.problems(bytes, corpus, results)
  abort ["registry failed:", *problems].join("\n  ") unless problems.empty?

  entries = JSON.parse(bytes)["entries"]
  puts(entries.empty? ? "registry: no claim is made" : "registry: #{entries.size} entries pass today")
  puts Conformance::Runner.unclaimed_lines(corpus, entries, Conformance::Records.reference_entries)
  puts Conformance::Runner.gap_lines(corpus, entries, results)
end

# The only writer of conformance/registry.json: it runs the whole corpus now
# and adds every case the run observed to pass.
desc "Run the corpus and record every observed pass in conformance/registry.json; " \
     "rake \"ratchet[scion]\" records the passes of the named suites only"
task :ratchet, [:suites] do |_task, args|
  corpus = Conformance::Corpus.load
  suites = args[:suites] ? [args[:suites], *args.extras] : Conformance::SUITES
  unknown = suites - Conformance::SUITES
  abort "ratchet refused; nothing was written: unknown suite #{unknown.join(", ")}" unless unknown.empty?

  problems = Conformance::Ratchet.write(Conformance::Registry::PATH, corpus, Conformance::Runner.run(corpus), suites:)
  abort ["ratchet refused; nothing was written:", *problems].join("\n  ") unless problems.empty?

  puts "ratchet: wrote conformance/#{Conformance::REGISTRY_FILE}"
end

# The publish step of .github/workflows/release.yml, which publishes through
# rubygems/release-gem: that action runs `bundle exec rake release` once it
# has exchanged the run's OIDC identity for a short-lived rubygems.org
# credential (trusted publishing), and afterwards waits for the gem it finds
# under pkg/ to appear on rubygems.org. The task builds the gem into pkg/ and
# pushes it. Unlike Bundler's own release task it never creates or pushes a
# git tag: the workflow runs on the push of the version tag, so the tag
# already exists.
#
# Anywhere but that workflow, on the push of the tag naming
# Statifier::VERSION, it refuses before building anything: a person or an
# agent never publishes from a checkout (CLAUDE.md, "Release preps"). The
# guard is a tripwire against an accidental `rake release`, not a security
# boundary.
module ReleaseTask
  # The repository whose release.yml may publish the gem.
  REPOSITORY = "riddler/statifier-rb"

  # Why the release task must not run under env (the process environment)
  # for the gem at version, or nil when it may: only GitHub Actions, on the
  # push of the tag vVERSION, in REPOSITORY's release.yml.
  def self.refusal(env, version)
    tag = "v#{version}"
    workflow = "#{REPOSITORY}/.github/workflows/release.yml@refs/tags/#{tag}"
    return if env["GITHUB_ACTIONS"] == "true" && env["GITHUB_REPOSITORY"] == REPOSITORY &&
              env["GITHUB_REF"] == "refs/tags/#{tag}" &&
              env["GITHUB_WORKFLOW_REF"] == workflow

    "release: runs only in .github/workflows/release.yml on the push of #{tag}; nothing was built or pushed"
  end
end

desc "Build and push the gem (only inside .github/workflows/release.yml on its version tag)"
task :release do
  require "bundler/gem_helper"

  helper = Bundler::GemHelper.new(__dir__, "statifier")
  refusal = ReleaseTask.refusal(ENV, helper.gemspec.version)
  abort refusal if refusal

  dirty = !system("git", "diff", "--quiet") || !system("git", "diff", "--cached", "--quiet")
  abort "release: the checkout has uncommitted changes; nothing was built or pushed" if dirty

  sh "gem", "push", helper.build_gem
end

# The full gate.
task default: %i[rubocop corpus:check registry test]
