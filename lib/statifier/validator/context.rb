# frozen_string_literal: true

module Statifier
  module Validator
    # The index the checks share: built once per {Validator.validate} call
    # from the chart and discarded with it, never kept or handed on.
    #
    # - `source`: the document as UTF-8, so that its byte offsets slice it;
    # - `states`: every state in document order, a parent before its
    #   children;
    # - `by_id`: each named state by its id; a repeated id keeps the last
    #   state written with it;
    # - `parents`: each state's parent, another state or the {Document} for a
    #   top-level one, keyed by the state node itself (by identity);
    # - `transitions`: every transition, as `[transition, owner]`, in
    #   document order; `owner` is `:plain` for a state's own, `:initial` for
    #   one inside a state's `<initial>`, and `:history` for a history's own;
    # - `invoke_content_markup`: whether a root that declares no namespace
    #   is accepted.
    #
    # @api private
    Context = ::Data.define(:source, :states, :by_id, :parents, :transitions, :invoke_content_markup) do
      # Whether `state` sits inside `ancestor`, by the tree's structure: a
      # state with no id, and two states that share one, are placed all the
      # same.
      def inside?(state, ancestor)
        parent = parents.fetch(state)
        parent.is_a?(Document::State) && (parent.equal?(ancestor) || inside?(parent, ancestor))
      end
    end

    # Building the {Context}.
    #
    # @api private
    module Index
      module_function

      # The {Context} of `document`, read from `source`.
      def build(document, source, invoke_content_markup)
        states = []
        parents = {}.compare_by_identity
        walk(document.states, document, states, parents)
        by_id = states.each_with_object({}) { |state, ids| ids[state.id] = state unless state.id.nil? }
        Context.new(source:, states: states.freeze, by_id: by_id.freeze, parents: parents.freeze,
                    transitions: states.flat_map { owned_transitions(_1) }.freeze, invoke_content_markup:)
      end

      # Collects every state below `parent` in document order, with its
      # parent.
      def walk(children, parent, states, parents)
        children.each do |state|
          states << state
          parents[state] = parent
          walk(state.states, state, states, parents)
        end
      end

      # A state's own transitions, then its `<initial>` element's; a
      # history's own only.
      def owned_transitions(state)
        return state.transitions.map { [_1, :history] } if state.kind == :history

        initial = state.initial_element&.transitions || Lowering::Reading::EMPTY
        state.transitions.map { [_1, :plain] } + initial.map { [_1, :initial] }
      end

      # Whether `node` is a `<state>` or `<parallel>` with children to
      # enter; the root is not.
      def compound?(node)
        node.is_a?(Document::State) && %i[state parallel].include?(node.kind) && !node.states.empty?
      end
    end
  end
end
