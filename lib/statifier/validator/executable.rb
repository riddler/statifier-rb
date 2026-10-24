# frozen_string_literal: true

module Statifier
  module Validator
    # The checks of executable content and of `<invoke>`.
    #
    # Each reaches the nodes the reference's own check reaches. Every check
    # reads a state's `<onentry>` and `<onexit>` blocks, its transitions and
    # its `<initial>` element's, descending into `<if>` branches and
    # `<foreach>` bodies; the `<send>` and `<cancel>` checks also read every
    # `<invoke>`'s `<finalize>`, and the `<script>` check the root's
    # scripts. A `<send>`'s `<content>` is not read by the `<content>` check.
    #
    # @api private
    module Executable
      # Whether both attributes were written.
      BOTH = ->(node, name, partner) { !node.public_send(name).nil? && !node.public_send(partner).nil? }

      # The rules of an `<invoke>`, in the reference's order.
      INVOKE_RULES = {
        invoke_type_and_typeexpr: ->(node) { BOTH.call(node, :type, :typeexpr) },
        invoke_src_and_srcexpr: ->(node) { BOTH.call(node, :src, :srcexpr) },
        invoke_src_and_content: ->(node) { !node.content.nil? && !(node.src || node.srcexpr).nil? },
        invoke_id_and_idlocation: ->(node) { BOTH.call(node, :id, :idlocation) },
        invoke_namelist_and_param: ->(node) { !node.namelist.empty? && !node.params.empty? }
      }.freeze

      # The targets a delay may not be written beside.
      INTERNAL = %w[_internal #_internal].freeze

      # The rules of a `<send>`, in the reference's order. A delay beside an
      # internal target is refused only when the target is written literally:
      # with `targetexpr` it is not known before the send executes.
      SEND_RULES = {
        send_event_and_eventexpr: ->(node) { BOTH.call(node, :event, :eventexpr) },
        send_target_and_targetexpr: ->(node) { BOTH.call(node, :target, :targetexpr) },
        send_type_and_typeexpr: ->(node) { BOTH.call(node, :type, :typeexpr) },
        send_id_and_idlocation: ->(node) { BOTH.call(node, :id, :idlocation) },
        send_delay_and_delayexpr: ->(node) { BOTH.call(node, :delay, :delayexpr) },
        send_delay_and_internal_target: lambda do |node|
          INTERNAL.include?(node.target) && !(node.delay || node.delayexpr).nil?
        end,
        send_namelist_and_content: ->(node) { !node.namelist.empty? && !node.content.nil? },
        send_param_and_content: ->(node) { !node.params.empty? && !node.content.nil? }
      }.freeze

      # The element a `<finalize>` may not hold, by node class.
      FORBIDDEN_IN_FINALIZE = { Document::Raise => "raise", Document::Send => "send" }.freeze

      module_function

      # Every node of a state's blocks and transitions, in document order, a
      # composite before what it holds.
      def state_nodes(state)
        initial = state.initial_element&.transitions || Lowering::Reading::EMPTY
        content = [*state.onentry, *state.onexit, *state.transitions, *initial].flat_map(&:content)
        content.flat_map { descend(_1) }
      end

      # The nodes of every `<finalize>` of a state's `<invoke>` children.
      def finalize_nodes(state) = state.invoke.filter_map(&:finalize).flat_map(&:content).flat_map { descend(_1) }

      # `node` and every node an `<if>` or `<foreach>` holds below it.
      def descend(node)
        inner = case node
                when Document::If then node.branches.flat_map(&:content)
                when Document::Foreach then node.content
                else Lowering::Reading::EMPTY
                end
        [node, *inner.flat_map { descend(_1) }]
      end

      # Every `<send>`, its `<finalize>` ones included.
      def sends(context)
        context.states.flat_map { state_nodes(_1) + finalize_nodes(_1) }.grep(Document::Send)
      end

      # An `<assign>` does not carry both `expr` and child content, markup or
      # text that is not blank; at the element's span.
      def assigns(_document, context)
        context.states.flat_map { state_nodes(_1) }.grep(Document::Assign).filter_map do |assign|
          next if assign.expr.nil? || (assign.markup.nil? && Lowering::Reading.blank?(assign.text))

          Findings.error(:assign_expr_and_text, assign.node_location, expr: assign.expr)
        end
      end

      # Every branch after an `<if>`'s first `<else>` is out of order: another
      # `<else>` is a duplicate, an `<elseif>` follows it.
      def ifs(_document, context)
        context.states.flat_map { state_nodes(_1) }.grep(Document::If).flat_map do |node|
          after_else = node.branches.drop_while { !_1.cond.nil? }.drop(1)
          after_else.map do |branch|
            Findings.error(branch.cond.nil? ? :if_duplicate_else : :if_elseif_after_else, branch.location)
          end
        end
      end

      # A `<script>` has a program: text that is not blank.
      def scripts(document, context)
        all = context.states.flat_map { state_nodes(_1) }.grep(Document::Script) + document.scripts
        all.select { Lowering::Reading.blank?(_1.text) }.map { Findings.error(:script_no_src_or_text, _1.location) }
      end

      # An `<invoke>`'s exclusive pairs, each at its span.
      def invokes(_document, context) = broken(context.states.flat_map(&:invoke), INVOKE_RULES)

      # A `<send>`'s exclusive pairs, each at its span.
      def sends_check(_document, context) = broken(sends(context), SEND_RULES)

      # A `<cancel>` carries exactly one of `sendid` and `sendidexpr`.
      def cancels(_document, context)
        all = context.states.flat_map { state_nodes(_1) + finalize_nodes(_1) }.grep(Document::Cancel)
        all.filter_map do |cancel|
          written = [cancel.sendid, cancel.sendidexpr].compact.size
          next if written == 1

          Findings.error(written.zero? ? :cancel_no_sendid : :cancel_sendid_and_sendidexpr, cancel.location)
        end
      end

      # The error of each rule each node breaks, at the node's span.
      def broken(nodes, rules)
        nodes.flat_map do |node|
          rules.select { |_, rule| rule.call(node) }.keys.map { Findings.error(_1, node.location) }
        end
      end

      # The warning: a `<raise>` or `<send>` inside a `<finalize>`, at its own
      # span.
      def finalize_warnings(_document, context)
        context.states.flat_map { finalize_nodes(_1) }.filter_map do |node|
          element = FORBIDDEN_IN_FINALIZE[node.class]
          Findings.warning(:finalize_forbidden_content, node.location, element:) if element
        end
      end
    end
  end
end
