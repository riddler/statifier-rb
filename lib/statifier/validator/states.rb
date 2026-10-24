# frozen_string_literal: true

module Statifier
  module Validator
    # The checks of ids, targets and initial references. Each check takes
    # the chart and the {Context} and answers its errors.
    #
    # @api private
    module States
      module_function

      # Every id-typed attribute, a state's and a `<data>`'s, shares one
      # uniqueness set. An empty id is `:empty_id` and joins no set; the
      # first occurrence of an id in document order is canonical and each
      # later one is `:duplicate_id`, at its own span.
      def ids(document, _context)
        entries = in_order(data_ids(document.datamodel_element) + state_ids(document.states))
        empty, named = entries.reject { _1.first.nil? }.partition { _1.first == "" }
        empty.map { Findings.error(:empty_id, _1.last) } + duplicates(named)
      end

      # Each later entry of an id, the first being canonical.
      def duplicates(entries)
        entries.group_by(&:first).flat_map do |id, (_first, *later)|
          later.map { Findings.error(:duplicate_id, _1.last, id:) }
        end
      end

      # Id entries sorted by where their span starts, found order kept.
      def in_order(entries)
        entries.each_with_index.sort_by { |(_, location), index| [location.start_offset, index] }.map(&:first)
      end

      # The id entries of states, their datamodels' `<data>` included, in
      # tree order.
      def state_ids(states)
        states.flat_map do |state|
          [[state.id, span(state, :id)], *data_ids(state.datamodel_element), *state_ids(state.states)]
        end
      end

      # The id entries of a `<datamodel>`'s `<data>`.
      def data_ids(datamodel) = datamodel.nil? ? [] : datamodel.data.map { [_1.id, span(_1, :id)] }

      # Every transition's targets resolve. This check owns existence: the
      # checks after it skip an unresolved id rather than report it again.
      def targets(_document, context)
        context.transitions.flat_map do |transition, _owner|
          location = span(transition, :target)
          transition.target.reject { context.by_id.key?(_1) }.map do |id|
            Findings.error(:unresolved_target, location, id:)
          end
        end
      end

      # Every `initial` reference resolves and lands inside the state it
      # initializes; a state with nothing to default into is reported once
      # and nothing else is checked on it. The chart's own `initial` need
      # only resolve.
      def initial_targets(document, context)
        location = span(document, :initial)
        root = document.initial.reject { context.by_id.key?(_1) }.map do |id|
          Findings.error(:unresolved_initial, location, id:)
        end
        context.states.flat_map { initial_state(_1, context) } + root
      end

      # The initial-target errors of one state.
      def initial_state(state, context)
        return [] if state.initial.empty? && state.initial_element.nil?

        return [atomic(state)] if state.states.empty? || %i[parallel final history].include?(state.kind)

        initial_attribute(state, context) + initial_element_targets(state, context)
      end

      # The `:initial_on_atomic_state` error of a state with nothing to
      # default into: at its `initial`, else at its `<initial>`.
      def atomic(state)
        location = state.initial.empty? ? state.initial_element.location : span(state, :initial)
        Findings.error(:initial_on_atomic_state, location, id: state.id)
      end

      # The ids of a state's `initial` attribute.
      def initial_attribute(state, context)
        location = span(state, :initial)
        state.initial.filter_map do |id|
          if !context.by_id.key?(id)
            Findings.error(:unresolved_initial, location, id:)
          elsif outside?(id, state, context)
            Findings.error(:initial_not_descendant, location, id:, parent_id: state.id)
          end
        end
      end

      # The resolved targets of a state's `<initial>` that lie outside it.
      def initial_element_targets(state, context)
        transitions = state.initial_element&.transitions || Lowering::Reading::EMPTY
        transitions.flat_map { outside_targets(_1, state, context) }
      end

      # The `:initial_not_descendant` errors of a transition's resolved
      # targets outside `parent`.
      def outside_targets(transition, parent, context)
        location = span(transition, :target)
        transition.target.select { context.by_id.key?(_1) && outside?(_1, parent, context) }.map do |id|
          Findings.error(:initial_not_descendant, location, id:, parent_id: parent.id)
        end
      end

      # Whether the state `id` names lies outside `state`, by the tree.
      def outside?(id, state, context) = !context.inside?(context.by_id.fetch(id), state)

      # A state's `<initial>` element: not beside an `initial` attribute,
      # and one default transition.
      def initial_elements(_document, context)
        context.states.reject { _1.initial_element.nil? }.flat_map do |state|
          element = state.initial_element
          owner = { kind: :initial, id: state.id }
          both_forms(state) + default_transition(owner, element.transitions, element.location)
        end
      end

      # The `:initial_attribute_and_element` error of a state with both.
      def both_forms(state)
        return [] if state.initial.empty?

        [Findings.error(:initial_attribute_and_element, state.initial_element.location, id: state.id)]
      end

      # The content model an `<initial>` and a history share: exactly one
      # transition, with a target, and neither `event` nor `cond`. A wrong
      # count is reported at the owner.
      def default_transition(owner, transitions, owner_location)
        count = transitions.size == 1 ? [] : [transitions.size]
        count.map { Findings.error(:transition_count, owner_location, owner:, count: _1) } +
          transitions.flat_map { missing_target(owner, _1) + forbidden(owner, _1) }
      end

      # The `:transition_missing_target` error of a default transition with
      # no target.
      def missing_target(owner, transition)
        return [] unless transition.target.empty?

        [Findings.error(:transition_missing_target, transition.location, owner:)]
      end

      # A default transition's written `event` and `cond`: an empty `event`
      # lowers to an empty list, so only its span says it was written.
      def forbidden(owner, transition)
        written = { event: transition.attribute_locations.key?(:event), cond: !transition.cond.nil? }
        written.select { |_, yes| yes }.keys.map do |attribute|
          Findings.error(:transition_forbidden_attribute, span(transition, attribute), owner:, attribute:)
        end
      end

      # The value span of an attribute when it was written, else the node's.
      def span(node, key) = node.attribute_locations.fetch(key, node.location)
    end
  end
end
