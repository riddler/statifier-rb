# frozen_string_literal: true

SimpleCov.start do
  enable_coverage :branch
  coverage_dir "coverage"
  track_files "lib/**/*.rb"
  add_filter "/test/"
  # The coverage minimum is the library's. The release task's test loads the
  # Rakefile to ask its guard, and a loaded file is otherwise counted too.
  add_filter "/Rakefile"
  minimum_coverage 90
end
