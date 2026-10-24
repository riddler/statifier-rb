# frozen_string_literal: true

module Statifier
  module Compiler
    # The state half of the {Walk}. A state takes its index when the walk
    # reaches it, before its children; then its own `<onentry>` and
    # `<onexit>` content, its transitions (a history's are its default; any
    # other kind's plain transitions come before its `<initial>` element's)
    # with their content, its `<donedata>`, its `<data>`, and its `<invoke>`
    # elements with their `<finalize>` content are numbered before the walk
    # descends. A transition's targets can name a state the walk has not
    # reached yet, so targets are resolved, and conditions compiled, once the
    # walk is done.
    #
    # @api private
    module Numbering
      EMPTY = [].freeze

      # The parts the root has none of.
      ROOT_PARTS = {
        transitions: EMPTY, onentry: EMPTY, onexit: EMPTY, initial_transition: nil, history_default: nil,
        donedata: nil, invoke: EMPTY
      }.freeze

      PendingTransition = ::Data.define(:transition, :source, :t_index, :content)

      # The fields a compiled state copies from its document node.
      COPIED = %i[id kind history_type location attribute_locations].freeze

      private

      # Numbers one group of sibling states and their subtrees, depth first,
      # from `index`; answers the group's indexes and the first index after
      # the whole group.
      def siblings(states, index, parent)
        indexes = states.map do |state|
          own = index
          index = numbered(state, own, parent)
          own
        end
        [indexes.freeze, index]
      end

      # Numbers `state` at `index` and its subtree; answers the first index
      # after the subtree.
      def numbered(state, index, parent)
        own = own_parts(state, index)
        children, after = siblings(state.states, index + 1, index)
        @states[index] = Machine::State.new(
          index:, parent:, last: after - 1, children:, **own, **state.to_h.slice(*COPIED),
          initial: resolve_initial(state, children), history_children: histories(children)
        )
        @id_to_index[state.id] = index unless state.id.nil?
        after
      end

      # The parts of a state numbered before its children, in the order the
      # walk numbers them.
      def own_parts(state, index)
        parts = { onentry: blocks(state.onentry), onexit: blocks(state.onexit) }
        parts.merge!(transition_parts(state, index))
        parts.merge!(data_parts(state, index))
      end

      # A state's `<donedata>`, then its `<data>`, then its `<invoke>`s.
      def data_parts(state, index)
        donedata = state.donedata && build_donedata(state.donedata, index)
        assign_data(state.datamodel_element, index)
        invoke = state.invoke.each_with_index.map { |node, at| build_invoke(node, index, at) }.freeze
        { donedata:, data: owned_data(index), invoke: }
      end

      # A history's transitions are its default; any other kind's plain
      # transitions are selectable, and its `<initial>` element's follow.
      def transition_parts(state, index)
        plain = numbered_transitions(state.transitions, index)
        return { transitions: EMPTY, initial_transition: nil, history_default: plain.first } if state.kind == :history

        initial = numbered_transitions(state.initial_element&.transitions || EMPTY, index)
        { transitions: plain, initial_transition: initial.first, history_default: nil }
      end

      def numbered_transitions(transitions, source)
        transitions.map do |transition|
          content = content_list(transition.content)
          @pending << PendingTransition.new(transition:, source:, t_index: @pending.size, content:)
          @pending.size - 1
        end.freeze
      end

      def build_transition(pending)
        transition = pending.transition
        fields = pending.to_h.slice(:t_index, :source, :content)
                        .merge(transition.to_h.slice(:type, :location, :attribute_locations))
        Machine::Transition.new(
          targets: resolve(transition.target), events: events(transition.event),
          **transition_cond(transition, pending.t_index), **fields
        )
      end

      # Each event descriptor split on its dots, an empty part kept.
      def events(descriptors) = descriptors.map { _1.split(".", -1).map(&:freeze).freeze }.freeze

      # A transition's condition compiled, a load-time error, and where it
      # was written; both nil when none was.
      def transition_cond(transition, t_index)
        return { cond: nil, cond_location: nil } if transition.cond.nil?

        cond_location = span(transition, :cond)
        site = site({ kind: :transition, t_index: }, "transition", "cond", cond_location)
        { cond: load_time(:transitions, transition.cond, site), cond_location: }
      end

      # A `<state>`'s default entry, in the specification's precedence.
      # Only a `<state>` has one: a parallel enters every child, and a final
      # or history is never entered by default.
      def resolve_initial(state, children)
        return EMPTY unless state.kind == :state
        return resolve(state.initial) unless state.initial.empty?

        written = state.initial_element&.transitions || EMPTY
        written.size == 1 ? resolve(written.first.target) : children.first(1).freeze
      end

      # The indexes of `ids`; the validator has resolved every one.
      def resolve(ids) = ids.map { @id_to_index.fetch(_1) }.freeze

      def histories(children) = children.select { @states.fetch(_1).kind == :history }.freeze

      def blocks(blocks) = blocks.map { block(_1) }.freeze

      def block(block) = Machine::Block.new(location: block.location, content: content_list(block.content))

      def assign_data(datamodel, state_index)
        datamodel&.data&.each do |node|
          d_index = @data.size
          @data << data_element(node, d_index)
          @data_by_state[state_index] << d_index
        end
      end

      def owned_data(index) = @data_by_state.fetch(index, EMPTY).dup.freeze
    end
  end
end
