# frozen_string_literal: true

module Statifier
  module Lowering
    # The builders of `<if>`, `<elseif>`, `<else>` and `<foreach>`.
    #
    # @api private
    module Executable
      module_function

      # An `<if>` is folded into partitions: the first branch is the `<if>`'s
      # own, each `<elseif>` or `<else>` opens the next, and executable
      # content joins whichever branch is open.
      def if_node(element, source)
        results, errors = Lowering.walk_children(element, source)
        cond = Reading.value(element, "cond")
        return [nil, errors + [Errors.missing_attribute("if", "cond", element.location)]] if cond.nil?

        first = branch(element, cond, Reading.locations(element, %w[cond]))
        branches, misplaced = partition(results, first, element.name)
        [[:content_node, Document::If.new(location: element.location, branches:)], errors + misplaced]
      end

      # An `<elseif>` takes no children; it is a partition mark for its `<if>`.
      def elseif(element, _source)
        errors = misplaced_children(element, "elseif")
        cond = Reading.value(element, "cond")
        return [nil, errors + [Errors.missing_attribute("elseif", "cond", element.location)]] if cond.nil?

        [[:elseif, branch(element, cond, Reading.locations(element, %w[cond]))], errors]
      end

      # An `<else>` takes no attributes: the first one written is refused,
      # and the branch is made all the same.
      def else_node(element, _source)
        errors = misplaced_children(element, "else")
        first = element.attributes.first
        errors += [Errors.unexpected_attribute("else", first.name, first.location)] if first
        [[:else, branch(element, nil, Reading::NO_LOCATIONS)], errors]
      end

      # Both required attributes are checked before the node is given up, so
      # a `<foreach>` missing both reports both.
      def foreach(element, source)
        results, errors = Lowering.walk_children(element, source)
        missing = %w[item array].select { |name| Reading.value(element, name).nil? }
        unless missing.empty?
          return [nil, errors + missing.map { Errors.missing_attribute("foreach", _1, element.location) }]
        end

        filled, misplaced = Placement.fold(results, Placement::CONTENT, element.name)
        [[:content_node, foreach_node(element, Placement.many(filled, :content))], errors + misplaced]
      end

      # The node of a `<foreach>` whose required attributes were written.
      def foreach_node(element, content)
        Document::Foreach.new(
          location: element.location, array: Reading.value(element, "array"), item: Reading.value(element, "item"),
          index: Reading.value(element, "index"), content:,
          attribute_locations: Reading.locations(element, %w[array item index])
        )
      end

      # A branch opened by `element`, holding no content yet.
      def branch(element, cond, attribute_locations)
        Document::If::Branch.new(location: element.location, cond:, content: Reading::EMPTY, attribute_locations:)
      end

      # Folds an `<if>`'s lowered children into its branches.
      def partition(results, first, parent_name)
        open = [[first, []]]
        errors = []
        results.compact.each do |tag, node|
          case tag
          when :content_node then open.last.last << node
          when :elseif, :else then open << [node, []]
          else errors.unshift(Placement.misplaced(tag, node, parent_name))
          end
        end
        [open.map { |opened, content| opened.with(content: content.freeze) }.freeze, errors]
      end
    end
  end
end
