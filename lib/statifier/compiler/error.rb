# frozen_string_literal: true

module Statifier
  module Compiler
    # Why a chart did not compile: a reason symbol, the detail that reason
    # carries (a frozen Hash), a message for a person, and the span reported.
    # The shape of {Lowering::Error} and {Validator::Error}.
    #
    # The one reason is `:expression_compile_error`, an expression or
    # program that predicator refused. Its detail:
    #
    # - `owner`: the node the expression belongs to, a frozen Hash in the
    #   machine's index spaces: `{kind: :transition, t_index:}`,
    #   `{kind: :content, c_index:}`, `{kind: :donedata, state_index:}`,
    #   `{kind: :data, d_index:}`, `{kind: :global_script, index:}` or
    #   `{kind: :invoke, state_index:, invoke_index:}`;
    # - `element` and `attribute`: where it was written, as Strings
    #   (`"transition"` and `"cond"`); a `<script>` body, written as the
    #   element's text, has the element `"script"` and a nil attribute;
    # - `source`: the expression as written;
    # - `error`: predicator's own `Predicator::ParseError`, its position in
    #   the expression's own lines and columns.
    #
    # The span is the attribute's value when one was written, and the element
    # otherwise.
    #
    # @api private
    Error = ::Data.define(:reason, :detail, :message, :location)
  end
end
