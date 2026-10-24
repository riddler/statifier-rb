# frozen_string_literal: true

require_relative "statifier/version"
require_relative "statifier/xml"
require_relative "statifier/lowering"
require_relative "statifier/validator"

# The interpreter core of an SCXML statechart engine.
#
# The package is being rewritten for 0.1.0. It holds the reader that turns a
# document into an element tree ({Statifier::XML}, internal) and the
# lowering that turns that tree into a typed chart ({Statifier::Lowering}
# and {Statifier::Document}, internal), and the validator that holds the
# chart to the rules that gate compilation ({Statifier::Validator},
# internal); the compiler and the interpreter arrive with later changes.
module Statifier
end
