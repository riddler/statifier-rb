# frozen_string_literal: true

require "test_helper"

# The version file and the gemspec that reads it. The gemspec is loaded, never
# built, and nothing here requires the predicator gem.
class VersionTest < Minitest::Test
  GEMSPEC = File.expand_path("../statifier.gemspec", __dir__)

  # sabotage: change VERSION to "0.1.0.pre"; the assertion on "0.1.0" fails.
  def test_version_is_the_first_release_of_the_rewrite
    assert_equal "0.1.0", Statifier::VERSION
  end

  # sabotage: make the gemspec read a fixed "0.0.0"; the assertion that the
  # gem version equals Statifier::VERSION fails.
  def test_gemspec_reads_the_version_from_the_version_file
    spec = Gem::Specification.load(GEMSPEC)

    assert_equal Statifier::VERSION, spec.version.to_s
  end

  # sabotage: add spec.add_dependency "json" to the gemspec; the assertion
  # that the runtime dependency names are exactly ["predicator"] fails.
  def test_gemspec_declares_predicator_as_the_one_runtime_dependency
    spec = Gem::Specification.load(GEMSPEC)

    assert_equal ["predicator"], spec.runtime_dependencies.map(&:name)
  end

  # sabotage: widen the requirement to "< 4" in the gemspec; the assertion on
  # the requirement string fails.
  def test_gemspec_bounds_predicator_to_the_second_major_version
    spec = Gem::Specification.load(GEMSPEC)
    requirement = spec.runtime_dependencies.first.requirement

    clauses = requirement.as_list.sort

    assert_equal ["< 3", ">= 2.0"], clauses
  end

  # sabotage: add Dir.glob("conformance/**/*") to the gemspec's files; the
  # assertion that every shipped file is under lib/ or a top-level document
  # fails.
  def test_gemspec_ships_lib_and_the_documents_only
    spec = Gem::Specification.load(GEMSPEC)

    refute_empty spec.files
    assert(spec.files.all? { |file| file.start_with?("lib/") || %w[README.md CHANGELOG.md LICENSE].include?(file) },
           "the gem ships #{spec.files.reject { |file| file.start_with?("lib/") }.inspect}")
  end

  # sabotage: set required_ruby_version to ">= 3.2" in the gemspec; the
  # assertion on the requirement string fails.
  def test_gemspec_requires_ruby_3_3_or_later
    spec = Gem::Specification.load(GEMSPEC)

    assert_equal ">= 3.3", spec.required_ruby_version.to_s
  end

  # sabotage: drop the rubygems_mfa_required line from the gemspec; the
  # assertion that the metadata is "true" fails.
  def test_gemspec_requires_mfa_for_publishing
    spec = Gem::Specification.load(GEMSPEC)

    assert_equal "true", spec.metadata["rubygems_mfa_required"]
  end

  # sabotage: point source_code_uri at another repository; the assertion on
  # the URL fails.
  def test_gemspec_names_the_repository
    spec = Gem::Specification.load(GEMSPEC)

    assert_equal "https://github.com/riddler/statifier-rb", spec.metadata["source_code_uri"]
    assert_equal "https://github.com/riddler/statifier-rb/blob/main/CHANGELOG.md", spec.metadata["changelog_uri"]
  end
end
