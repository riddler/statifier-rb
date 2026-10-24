# frozen_string_literal: true

require "minitest/test_task"
require "rubocop/rake_task"

RuboCop::RakeTask.new

# The suite runs under SimpleCov (configured in .simplecov), which fails the
# run below the coverage minimum. SimpleCov is required in the prelude, ahead
# of minitest/autorun, so that it reports after the suite has run rather than
# before it.
Minitest::TestTask.create(:test) do |t|
  t.test_prelude = %(require "simplecov")
  t.test_globs = ["test/**/*_test.rb"]
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
task default: %i[rubocop test]
