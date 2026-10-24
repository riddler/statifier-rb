# frozen_string_literal: true

# SimpleCov starts before lib/ is loaded, or the loaded lines go uncounted.
# Under `rake test` the task's prelude has already required it; this line
# covers a test file run on its own.
require "simplecov"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "statifier"

require "minitest/autorun"

# The package's internal modules are private constants of Statifier, and the
# driver's internals of Statifier::Driver; the unit tests reach them by name
# here, as predicator's tests reach its own.
module Internals
  %i[Accepts Compiler Datamodel Document Frozen Interpreter Lowering Machine Validator XML].each do |name|
    const_set(name, Statifier.const_get(name))
  end

  SessionId = Statifier::Driver.const_get(:SessionId)
end
