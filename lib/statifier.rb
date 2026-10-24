# frozen_string_literal: true

require_relative "statifier/version"
require_relative "statifier/xml"

# The interpreter core of an SCXML statechart engine.
#
# The package is being rewritten for 0.1.0. It holds the reader that turns a
# document into an element tree ({Statifier::XML}, internal); the compiler
# and the interpreter arrive with later changes.
module Statifier
end
