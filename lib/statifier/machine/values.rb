# frozen_string_literal: true

module Statifier
  class Machine
    # An expression compiled by `Predicator.compile`: its `instructions`, the
    # list predicator evaluates, and its `source`, as written.
    #
    # @api private
    Compiled = ::Data.define(:instructions, :source)

    # A statement program (a `<script>` body) compiled by
    # `Predicator.compile_program`: its `instructions`, the list predicator
    # executes, and its `source`, as written.
    #
    # @api private
    Program = ::Data.define(:instructions, :source)

    # A value fixed when the chart compiled, with nothing to evaluate: a
    # literal attribute, a `<content>` body, or an in-line `<data>` or
    # `<assign>` value.
    #
    # @api private
    Static = ::Data.define(:value)

    # An expression or program that did not compile, where the failure is
    # deferred to when it runs: `error` is the {Compiler::Error} the compile
    # answered.
    #
    # @api private
    Invalid = ::Data.define(:error)

    # A `<data>` value the host resolves: `src` as written.
    #
    # @api private
    Src = ::Data.define(:src)
  end
end
