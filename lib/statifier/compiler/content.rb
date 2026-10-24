# frozen_string_literal: true

module Statifier
  module Compiler
    # The executable content half of the {Walk}: each content node compiled,
    # taking the next content index first, so a container's index precedes
    # its children's.
    #
    # A refusal is one of two things, class by class, as in the reference.
    # A transition's `cond`, a `<log>`'s `expr`, an `<if>` or `<elseif>`
    # condition, a `<foreach>`'s `array`, a `<cancel>`'s `sendidexpr`, and a
    # `<send>`'s expressions, `<content>` and `<param>`s are load-time
    # errors: the chart does not compile. An `<assign>`'s `expr` and a
    # `<script>` body are deferred: the node holds a {Machine::Invalid} that
    # fails when it runs.
    #
    # @api private
    module Content
      # The builder of each kind of content node.
      BUILDERS = {
        Document::Raise => :raise_node, Document::Log => :log, Document::Assign => :assign,
        Document::If => :if_node, Document::Foreach => :foreach, Document::Script => :script,
        Document::Send => :send_node, Document::Cancel => :cancel
      }.freeze

      # A `<send>`'s attribute pairs, in the order they compile.
      SEND_PAIRS = [%i[event eventexpr], %i[target targetexpr], %i[type typeexpr], %i[delay delayexpr]].freeze

      # The content of a block, a transition, a branch or a loop body.
      def content_list(nodes) = nodes.map { __send__(BUILDERS.fetch(_1.class), _1, next_c_index) }.freeze

      private

      def content_site(c_index, element, attribute, location)
        site({ kind: :content, c_index: }, element, attribute, location)
      end

      def raise_node(node, c_index) = Machine::Raise.new(c_index:, event: node.event, location: node.location)

      def log(node, c_index)
        expr_location = node.expr && span(node, :expr)
        expr = node.expr && load_time(:content, node.expr, content_site(c_index, "log", "expr", expr_location))
        Machine::Log.new(c_index:, label: node.label, expr:, location: node.location, expr_location:)
      end

      # An `<assign>`'s value: its `expr`, a refusal deferred; else its
      # markup children as a string; else its text folded as an in-line
      # value; else nil.
      def assign(node, c_index)
        expr_location = node.expr && span(node, :expr, node.node_location)
        Machine::Assign.new(
          c_index:, location: node.location, node_location: node.node_location, value: assign_value(node, c_index),
          location_location: span(node, :location, node.node_location), expr_location:
        )
      end

      def assign_value(node, c_index)
        return text_value(node.markup, node.text) if node.expr.nil?

        site = content_site(c_index, "assign", "expr", span(node, :expr, node.node_location))
        Expressions.deferred(Expressions.compile(node.expr, site))
      end

      # Every branch's condition compiles, each refusal its own error.
      def if_node(node, c_index)
        branches = node.branches.each_with_index.map { |branch, position| branch(branch, position, c_index) }
        Machine::If.new(c_index:, location: node.location, branches: branches.freeze)
      end

      # One branch: the `<if>` itself at position 0, then each `<elseif>` and
      # `<else>`.
      def branch(branch, position, c_index)
        cond_location = branch.cond && span(branch, :cond)
        site = content_site(c_index, position.zero? ? "if" : "elseif", "cond", cond_location)
        cond = branch.cond && load_time(:content, branch.cond, site)
        Machine::If::Branch.new(cond:, cond_location:, content: content_list(branch.content))
      end

      def foreach(node, c_index)
        array_location = span(node, :array)
        array = load_time(:content, node.array, content_site(c_index, "foreach", "array", array_location))
        Machine::Foreach.new(
          c_index:, location: node.location, array:, array_location:, item: node.item,
          item_location: span(node, :item), index: node.index, index_location: node.index && span(node, :index),
          content: content_list(node.content)
        )
      end

      def script(node, c_index)
        program = Expressions.program(node.text, content_site(c_index, "script", nil, node.location))
        Machine::Script.new(c_index:, program:, node_location: node.location)
      end

      # A `<send>`: its attribute pairs, then its `<content>`, compile in
      # that order and the first refusal stops the rest, its `<param>`s
      # included; the `<param>`s then each answer their own refusal.
      def send_node(node, c_index)
        owner = { kind: :content, c_index: }
        folded, refusal = send_values(node, owner)
        record_all(:content, [refusal]) if refusal
        Machine::Send.new(
          c_index:, location: node.location, **folded, id: node.id, idlocation: node.idlocation,
          namelist: namelist(node, owner, "send"),
          params: refusal ? Numbering::EMPTY : params(:content, node.params, owner),
          attribute_locations: node.attribute_locations
        )
      end

      # The folded attribute pairs and `<content>` of a `<send>`, and the
      # first refusal among them.
      def send_values(node, owner)
        folded = { event: nil, target: nil, type: nil, delay: nil, content: nil }
        steps = SEND_PAIRS.map { |names| [names.first, -> { pair(node, names, owner, "send") }] }
        steps << [:content, -> { node.content && content_value(node.content, owner) }]
        steps.each do |key, step|
          value = step.call
          return [folded, value] if value.is_a?(Error)

          folded[key] = value
        end
        [folded, nil]
      end

      # A `<cancel>`: `sendid` as a literal, else `sendidexpr` compiled.
      def cancel(node, c_index)
        sendid = record_all(:content, [pair(node, %i[sendid sendidexpr], { kind: :content, c_index: }, "cancel")]).first
        Machine::Cancel.new(c_index:, location: node.location, sendid:, attribute_locations: node.attribute_locations)
      end
    end
  end
end
