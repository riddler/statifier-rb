# frozen_string_literal: true

require "test_helper"
require "rake"

# The Rakefile's `release` task is the publish step of the release workflow,
# and it must refuse everywhere but that workflow on the push of the tag
# naming Statifier::VERSION. The Rakefile is loaded into a throwaway Rake
# application; its guard, ReleaseTask.refusal, is asked about each
# environment, and the task's body is read as text to check that it consults
# the guard before it builds or pushes anything. The task itself is never run.
class ReleaseTaskTest < Minitest::Test
  RAKEFILE = File.expand_path("../Rakefile", __dir__)
  APPLICATION = Rake::Application.new
  Rake.with_application(APPLICATION) { load RAKEFILE }

  VERSION = Statifier::VERSION
  TAG = "v#{VERSION}".freeze
  REPOSITORY = "riddler/statifier-rb"

  # The variables GitHub Actions sets for release.yml on the push of tag.
  def release_workflow(tag)
    {
      "GITHUB_ACTIONS" => "true",
      "GITHUB_REF" => "refs/tags/#{tag}",
      "GITHUB_REPOSITORY" => REPOSITORY,
      "GITHUB_WORKFLOW_REF" => "#{REPOSITORY}/.github/workflows/release.yml@refs/tags/#{tag}"
    }
  end

  def assert_refused(env)
    refusal = ReleaseTask.refusal(env, VERSION)

    assert_equal "release: runs only in .github/workflows/release.yml on the push of #{TAG}; " \
                 "nothing was built or pushed", refusal
  end

  # The text of the release task's block in the Rakefile.
  def release_task_body
    File.read(RAKEFILE)[/^task :release do\n(.*?)^end$/m, 1]
  end

  # sabotage: make the guard return nil whatever the environment; the
  # assert_equal on the refusal message fails (nil is not the message).
  def test_refuses_outside_github_actions
    assert_refused({})
  end

  # sabotage: drop the GITHUB_ACTIONS comparison from the guard; the
  # assert_equal on the refusal message fails.
  def test_refuses_without_github_actions_set_even_with_the_workflow_refs
    env = release_workflow(TAG)
    env.delete("GITHUB_ACTIONS")

    assert_refused(env)
  end

  # sabotage: drop the GITHUB_WORKFLOW_REF comparison from the guard; the
  # assert_equal on the refusal message fails.
  def test_refuses_another_workflow_on_the_version_tag
    env = release_workflow(TAG)
    env["GITHUB_WORKFLOW_REF"] = "#{REPOSITORY}/.github/workflows/ci.yml@refs/tags/#{TAG}"

    assert_refused(env)
  end

  # sabotage: drop the GITHUB_REF comparison from the guard; the
  # assert_equal on the refusal message fails.
  def test_refuses_a_tag_that_does_not_name_the_version
    env = release_workflow(TAG)
    env["GITHUB_REF"] = "refs/tags/v#{VERSION}9"

    assert_refused(env)
  end

  # sabotage: drop the GITHUB_REPOSITORY comparison from the guard; the
  # assert_equal on the refusal message fails.
  def test_refuses_with_github_repository_unset
    env = release_workflow(TAG)
    env.delete("GITHUB_REPOSITORY")

    assert_refused(env)
  end

  # sabotage: compare GITHUB_ACTIONS against "1" rather than "true"; the
  # assert_nil on the guard's answer fails (it returns the message).
  def test_allows_release_yml_on_the_version_tag
    assert_nil ReleaseTask.refusal(release_workflow(TAG), VERSION)
  end

  # sabotage: delete the `abort refusal if refusal` line from the task; the
  # assertion that the abort is in the task body fails.
  def test_release_task_aborts_on_the_guard_before_building_or_pushing
    body = release_task_body

    refute_nil body, "the Rakefile defines no release task block"
    guard = body.index("refusal = ReleaseTask.refusal(ENV, helper.gemspec.version)")
    abort_line = body.index("abort refusal if refusal")

    refute_nil guard, "the task does not ask ReleaseTask.refusal about ENV"
    refute_nil abort_line, "the task does not abort on the refusal"
    assert_operator guard, :<, abort_line
    assert_operator abort_line, :<, body.index("helper.build_gem")
  end

  # sabotage: rename the task to :publish in the Rakefile; the assertion that
  # the throwaway application defines a release task fails.
  def test_release_task_is_defined
    assert APPLICATION.lookup("release"), "the Rakefile defines no release task"
  end
end
