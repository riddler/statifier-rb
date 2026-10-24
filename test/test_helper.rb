# frozen_string_literal: true

# SimpleCov starts before lib/ is loaded, or the loaded lines go uncounted.
# Under `rake test` the task's prelude has already required it; this line
# covers a test file run on its own.
require "simplecov"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "statifier"

require "minitest/autorun"
