# frozen_string_literal: true

module Statifier
  module Lowering
    # The builders of `<scxml>`, the state family, `<initial>`,
    # `<transition>` and the blocks. Each takes an element and the source,
    # and answers its node tagged with its place (the root's untagged) and
    # its errors.
    #
    # @api private
    module States
      ROOT_SLOTS = {
        state: %i[states many], datamodel: %i[datamodel_element one], Document::Script => %i[scripts many]
      }.freeze
      STATE_SLOTS = {
        state: %i[states many], transition: %i[transitions many], initial: %i[initial_element one],
        onentry: %i[onentry many], onexit: %i[onexit many], donedata: %i[donedata one],
        datamodel: %i[datamodel_element one], invoke: %i[invoke many]
      }.freeze
      INITIAL_SLOTS = { transition: %i[transitions many] }.freeze
      ROOT_ATTRIBUTES = %w[initial name datamodel binding version xmlns].freeze
      BINDINGS = { "early" => :early, "late" => :late }.freeze
      HISTORY_TYPES = { "shallow" => :shallow, "deep" => :deep }.freeze
      TRANSITION_TYPES = { "internal" => :internal, "external" => :external }.freeze

      module_function

      # `<scxml>`: answers the {Document} and its errors.
      def scxml(element, source)
        filled, errors = lower_children(element, source, ROOT_SLOTS)
        document = Document.new(
          location: element.location, **%i[name version xmlns datamodel].to_h { [_1, Reading.value(element, _1.to_s)] },
          namespace: element.namespace, binding: Reading.choice(element, "binding", BINDINGS, :early),
          initial: Reading.list(element, "initial"), states: Placement.many(filled, :states),
          datamodel_element: filled[:datamodel_element], scripts: Placement.many(filled, :scripts),
          attribute_locations: Reading.locations(element, ROOT_ATTRIBUTES)
        )
        [document, errors]
      end

      # The four state kinds share one builder; each answers a
      # {Document::State} tagged `:state`.
      def state(element, source) = state_like(element, source, :state)
      def parallel(element, source) = state_like(element, source, :parallel)
      def final(element, source) = state_like(element, source, :final)

      # A history's `type` lowers to `:shallow` when it is neither value, and
      # its location is kept so that a check can point at it.
      def history(element, source)
        (tag, state), errors = state_like(element, source, :history)
        locations = state.attribute_locations.merge(Reading.locations(element, %w[type])).freeze
        history_type = Reading.choice(element, "type", HISTORY_TYPES, :shallow)
        [[tag, state.with(history_type:, attribute_locations: locations)], errors]
      end

      # An `<initial>`: every `<transition>` child it holds.
      def initial(element, source)
        filled, errors = lower_children(element, source, INITIAL_SLOTS)
        [[:initial, Document::Initial.new(location: element.location,
                                          transitions: Placement.many(filled, :transitions))], errors]
      end

      # A `<transition>`: its attributes and its executable content.
      def transition(element, source)
        filled, errors = lower_children(element, source, Placement::CONTENT)
        node = Document::Transition.new(
          location: element.location, event: Reading.list(element, "event"),
          target: Reading.list(element, "target"), cond: Reading.value(element, "cond"),
          type: Reading.choice(element, "type", TRANSITION_TYPES, :external),
          content: Placement.many(filled, :content),
          attribute_locations: Reading.locations(element, %w[event target cond type])
        )
        [[:transition, node], errors]
      end

      # `<onentry>`, `<onexit>` and `<finalize>` each answer one block,
      # tagged with the element's name.
      def onentry(element, source) = block(element, source, :onentry)
      def onexit(element, source) = block(element, source, :onexit)
      def finalize(element, source) = block(element, source, :finalize)

      # One {Document::Block} per element, never flattened.
      def block(element, source, tag)
        filled, errors = lower_children(element, source, Placement::CONTENT)
        [[tag, Document::Block.new(location: element.location, content: Placement.many(filled, :content))], errors]
      end

      # A state of `kind`: its attributes and its children in their fields.
      def state_like(element, source, kind)
        filled, errors = lower_children(element, source, STATE_SLOTS)
        node = Document::State.new(
          kind:, location: element.location, id: Reading.value(element, "id"),
          initial: Reading.list(element, "initial"), initial_element: filled[:initial_element],
          states: Placement.many(filled, :states), transitions: Placement.many(filled, :transitions),
          onentry: Placement.many(filled, :onentry), onexit: Placement.many(filled, :onexit),
          history_type: nil, donedata: filled[:donedata], datamodel_element: filled[:datamodel_element],
          invoke: Placement.many(filled, :invoke), attribute_locations: Reading.locations(element, %w[id initial])
        )
        [[:state, node], errors]
      end

      # Walks an element's children and places them: answers the filled
      # fields and the walk's errors followed by the misplaced ones.
      def lower_children(element, source, slots)
        results, errors = Lowering.walk_children(element, source)
        filled, misplaced = Placement.fold(results, slots, element.name)
        [filled, errors + misplaced]
      end
    end
  end
end
