# frozen_string_literal: true

module Statifier
  module Validator
    # The checks of history states, final states and default entry.
    #
    # @api private
    module History
      HISTORY_TYPES = %w[shallow deep].freeze

      module_function

      # A history state: its parent is a compound `<state>` or `<parallel>`,
      # it has one default transition, that transition's resolved targets
      # lie inside the parent, and its `type` as written is in range.
      def histories(_document, context)
        context.states.select { _1.kind == :history }.flat_map do |state|
          parent = context.parents.fetch(state)
          compound = Index.compound?(parent)
          bad_parent(state, parent, compound) +
            default_transition(state) + outside_parent(state, parent, compound, context) +
            Enums.out_of_range(state, :type, HISTORY_TYPES, context, :history_bad_type)
        end
      end

      # A history's own transitions, as its one default transition.
      def default_transition(state)
        States.default_transition({ kind: :history, id: state.id }, state.transitions, state.location)
      end

      # The resolved default targets outside a compound parent; a parent
      # that is not compound is reported once, as such, and not tested.
      def outside_parent(state, parent, compound, context)
        compound ? state.transitions.flat_map { States.outside_targets(_1, parent, context) } : []
      end

      # The `:history_bad_parent` error of a history whose parent is not
      # compound; the root's kind is `:scxml`.
      def bad_parent(state, parent, compound)
        return [] if compound

        parent_kind = parent.is_a?(Document::State) ? parent.kind : :scxml
        [Findings.error(:history_bad_parent, state.location, id: state.id, parent_kind:)]
      end

      # A `<final>` holds no state and no transition: each is reported at its
      # own span.
      def finals(_document, context)
        context.states.select { _1.kind == :final }.flat_map do |state|
          state.states.map { Findings.error(:final_has_states, _1.location, id: _1.id) } +
            state.transitions.map { Findings.error(:final_has_transitions, _1.location, id: state.id) }
        end
      end

      # A state with a `<final>` child has an id, since the completion event
      # is named after it. Reported once per parent, at its span, naming its
      # first `<final>`.
      def final_parents(_document, context)
        context.states.filter_map do |state|
          first = state.states.find { _1.kind == :final }
          next if !state.id.nil? || first.nil?

          Findings.error(:final_parent_missing_id, state.location, final_id: first.id)
        end
      end

      # A `<state>` entered by default enters its first child, and a history
      # cannot be entered that way. A `<parallel>` enters every child, so it
      # is not read here.
      def default_entries(_document, context)
        context.states.filter_map do |state|
          first = state.states.first
          next unless state.kind == :state && state.initial.empty? && state.initial_element.nil?
          next unless first&.kind == :history

          Findings.error(:default_entry_not_enterable, first.location, id: state.id, child_kind: :history)
        end
      end
    end
  end
end
