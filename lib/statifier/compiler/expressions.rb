# frozen_string_literal: true

module Statifier
  module Compiler
    # Every expression of a chart compiles here, once, through predicator: a
    # condition or a value through `Predicator.compile`, a `<script>` body
    # through `Predicator.compile_program`, as the reference compiles them.
    #
    # @api private
    module Expressions
      # Where an expression was written: what a refusal names.
      Site = ::Data.define(:owner, :element, :attribute, :location)

      module_function

      # The expression `source` compiled: a {Machine::Compiled}, or the
      # {Error} predicator's refusal makes at `site`.
      def compile(source, site)
        result = Predicator.compile(source)
        result.ok? ? Machine::Compiled.new(instructions: result.value, source:) : refusal(source, result.error, site)
      end

      # The statement program `source` compiled: a {Machine::Program}, or an
      # {Machine::Invalid} carrying the {Error} predicator's refusal makes at
      # `site`. A program's refusal is always deferred to when it runs.
      def program(source, site)
        result = Predicator.compile_program(source)
        return Machine::Program.new(instructions: result.value, source:) if result.ok?

        Machine::Invalid.new(error: refusal(source, result.error, site))
      end

      # `compiled`, or an {Machine::Invalid} carrying it when it is an
      # {Error}: the deferral the reference gives `<assign expr>`,
      # `<data expr>` and a `namelist` entry.
      def deferred(compiled) = compiled.is_a?(Error) ? Machine::Invalid.new(error: compiled) : compiled

      # A literal value.
      def static(value) = Machine::Static.new(value:)

      # An in-line value (a `<data>` or `<assign>` body) folded to a literal:
      # the trimmed text compiled and evaluated against an empty context that
      # refuses every unbound name, and the trimmed text itself when either
      # step fails. So `[1, 2]` is a list, `3` a number, and `x` the string
      # `"x"` rather than a read of a variable.
      def inline_value(text)
        trimmed = Lowering::Errors.trim(text)
        compiled = Predicator.compile(trimmed)
        evaluated = compiled.ok? ? Predicator.evaluate(compiled.value, {}, on_unbound: :error) : compiled
        static(evaluated.ok? ? evaluated.value : trimmed)
      end

      # The {Error} for `parse_error` on `source`, with the reference's
      # message.
      def refusal(source, parse_error, site)
        position = parse_error.position
        message = "failed to compile expression #{Lowering::Errors.quote(source)}: #{parse_error.message} " \
                  "(predicator line #{position.line}, column #{position.column})"
        detail = { owner: site.owner, element: site.element, attribute: site.attribute, source:, error: parse_error }
        Error.new(reason: :expression_compile_error, detail:, message:, location: site.location)
      end
    end
  end
end
