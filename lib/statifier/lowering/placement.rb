# frozen_string_literal: true

module Statifier
  module Lowering
    # Placing a container's lowered children into its fields. A builder
    # answers its node tagged with the kind of place it goes in (`:state` for
    # the four state kinds, `:content_node` for executable content, the
    # element's own name for the rest); a container names the tags it has a
    # place for, and every other child is misplaced. Placement never looks at
    # the parent's element name except to word that error.
    #
    # @api private
    module Placement
      # The element name a misplaced executable node is reported under.
      NAMES = {
        Document::Raise => "raise", Document::Log => "log", Document::Assign => "assign",
        Document::If => "if", Document::Foreach => "foreach", Document::Script => "script",
        Document::Send => "send", Document::Cancel => "cancel"
      }.freeze

      # The places of a container whose one place is executable content.
      CONTENT = { content_node: %i[content many] }.freeze

      module_function

      # Folds `results` (the tagged children, nil for one that could not be
      # made) into the places `slots` names, `{tag => [field, :many | :one]}`;
      # a node class as a key places executable content of that class alone.
      # A `:many` field collects in document order, a `:one` field keeps the
      # last. Answers the filled fields and the misplaced errors, newest
      # first, as the reference accumulates them.
      def fold(results, slots, parent_name)
        filled = {}
        errors = []
        results.each do |result|
          next if result.nil?

          field, arity = slot_for(slots, *result)
          next errors.unshift(misplaced(*result, parent_name)) if field.nil?

          arity == :many ? (filled[field] ||= []) << result.last : filled[field] = result.last
        end
        [filled, errors]
      end

      # A `:many` field's nodes, frozen.
      def many(filled, field) = (filled[field] || Reading::EMPTY).freeze

      # The field and arity `slots` names for a tagged node, or nil.
      def slot_for(slots, tag, node)
        slots.fetch(tag) { tag == :content_node ? slots[node.class] : nil }
      end

      # The misplaced error for a tagged node its parent has no place for.
      def misplaced(tag, node, parent_name)
        return Errors.misplaced(NAMES.fetch(node.class), parent_name, span(node)) if tag == :content_node

        Errors.misplaced(tag.to_s, parent_name, node.location)
      end

      # An assign's `location` is its attribute; its span is `node_location`.
      def span(node) = node.is_a?(Document::Assign) ? node.node_location : node.location
    end
  end
end
