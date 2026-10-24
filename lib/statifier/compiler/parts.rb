# frozen_string_literal: true

module Statifier
  module Compiler
    # The data half of the {Walk}: `<data>`, `<donedata>`, `<param>`,
    # `<content>`, `namelist` and `<invoke>`, and the helpers every half
    # shares. A `<data>`'s `expr` and a `namelist` entry defer their refusal
    # to when they run; every other expression here is a load-time error.
    #
    # @api private
    module Parts
      private

      def site(owner, element, attribute, location) = Expressions::Site.new(owner:, element:, attribute:, location:)

      # Where `node` wrote the attribute `key`: its value's span, else
      # `fallback`, the element's span by default.
      def span(node, key, fallback = node.location) = node.attribute_locations[key] || fallback

      # `source` compiled at `site`, or nil with the refusal recorded in
      # `group`: a load-time error.
      def load_time(group, source, site)
        compiled = Expressions.compile(source, site)
        return compiled unless compiled.is_a?(Error)

        @groups.fetch(group) << compiled
        nil
      end

      # The values among `built`, each {Error} among them recorded in
      # `group`.
      def record_all(group, built)
        refused, kept = built.partition { _1.is_a?(Error) }
        @groups.fetch(group).concat(refused)
        kept.freeze
      end

      # A literal attribute folded with its `expr` twin: a static value for
      # the literal (the validator refuses a chart that writes both), the
      # twin compiled (a compiled value or an {Error}), or nil for neither.
      def pair(node, (literal, twin), owner, element)
        written = node.public_send(literal)
        return Expressions.static(written) unless written.nil?

        source = node.public_send(twin)
        source && Expressions.compile(source, site(owner, element, twin.to_s, span(node, twin)))
      end

      # A body with no `expr`: its markup children as a string, else its
      # text folded as an in-line value, else nil.
      def text_value(markup, text)
        return Expressions.static(markup) if markup
        return Expressions.static(nil) if Lowering::Reading.blank?(text)

        Expressions.inline_value(text)
      end

      # A `<content>`'s value: its `expr` compiled (a compiled value or an
      # {Error}), else its markup children, else its text, as written.
      def content_value(content, owner)
        return Expressions.static(content.markup || content.text) if content.expr.nil?

        Expressions.compile(content.expr, site(owner, "content", "expr", span(content, :expr)))
      end

      # A `<param>`: its `expr` when it has no `location`, else its
      # `location`, compiled; a {Machine::Param} or an {Error}. The
      # validator guarantees one of the two.
      def param(node, owner)
        kind = node.expr && node.param_location.nil? ? :expr : :location
        expr_location = span(node, node.expr.nil? ? :location : :expr)
        compiled = Expressions.compile(kind == :expr ? node.expr : node.param_location,
                                       site(owner, "param", kind.to_s, expr_location))
        return compiled if compiled.is_a?(Error)

        Machine::Param.new(name: node.name, kind:, expr: compiled, expr_location:, location: node.location)
      end

      def params(group, nodes, owner) = record_all(group, nodes.map { param(_1, owner) })

      # A `namelist`'s entries, each a location read by its own name, its
      # refusal deferred. The whole attribute shares one span.
      def namelist(node, owner, element)
        expr_location = span(node, :namelist)
        node.namelist.map do |name|
          expr = Expressions.deferred(Expressions.compile(name, site(owner, element, "namelist", expr_location)))
          Machine::Param.new(name:, kind: :location, expr:, expr_location:, location: node.location)
        end.freeze
      end

      # A `<data>`'s value, in the specification's precedence: `expr` (its
      # refusal deferred), then `src`, then its text, then nil.
      def data_element(node, d_index)
        value, value_location = data_value(node, d_index)
        Machine::Data.new(d_index:, id: node.id, value:, location: node.location, value_location:)
      end

      def data_value(node, d_index)
        if node.expr
          location = span(node, :expr)
          [Expressions.deferred(Expressions.compile(node.expr, site({ kind: :data, d_index: }, "data", "expr",
                                                                    location))), location]
        elsif node.src
          [Machine::Src.new(src: node.src), span(node, :src)]
        else
          [text_value(nil, node.text), node.location]
        end
      end

      # A final state's `<donedata>`: its `<content>`'s value, or its
      # `<param>`s.
      def build_donedata(node, state_index)
        owner = { kind: :donedata, state_index: }
        content = node.content
        if content.nil?
          return Machine::Donedata.new(location: node.location, expr: nil, expr_location: nil,
                                       params: params(:donedata, node.params, owner))
        end

        expr = record_all(:donedata, [content_value(content, owner)]).first
        expr_location = content.expr ? span(content, :expr) : content.markup_location || content.location
        Machine::Donedata.new(location: node.location, expr:, expr_location:, params: Numbering::EMPTY)
      end

      def build_invoke(node, state_index, invoke_index)
        owner = { kind: :invoke, state_index:, invoke_index: }
        Machine::Invoke.new(
          index: invoke_index, **invoke_values(node, owner), namelist: namelist(node, owner, "invoke"),
          params: params(:invoke, node.params, owner), finalize: node.finalize && block(node.finalize),
          **node.to_h.slice(:location, :id, :idlocation, :autoforward, :attribute_locations)
        )
      end

      # An `<invoke>`'s `type` and `src` pairs and its `<content>`, in that
      # order, each a load-time error.
      def invoke_values(node, owner)
        values = { type: pair(node, %i[type typeexpr], owner, "invoke"),
                   src: pair(node, %i[src srcexpr], owner, "invoke") }
        values[:content] = node.content && content_value(node.content, owner)
        values.transform_values { record_all(:invoke, [_1]).first }
      end
    end
  end
end
