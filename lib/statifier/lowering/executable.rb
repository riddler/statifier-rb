# frozen_string_literal: true

module Statifier
  module Lowering
    # The builders of executable content. A node that a required attribute
    # is missing from is not made: its builder answers nil and the error.
    #
    # @api private
    module Executable
      NO_SLOTS = {}.freeze
      SEND_SLOTS = { param: %i[params many], content: %i[content one] }.freeze
      SEND_ATTRIBUTES = %w[event eventexpr target targetexpr type typeexpr id idlocation delay delayexpr].freeze

      module_function

      # A `<raise>`'s `event` is one string, not split.
      def raise_node(element, source)
        required(element, source, NO_SLOTS, "event") do |event, _filled|
          [:content_node, Document::Raise.new(location: element.location, event:,
                                              attribute_locations: Reading.locations(element, %w[event]))]
        end
      end

      # A `<log>`: its `label` and `expr`; it takes no children.
      def log(element, source)
        _filled, errors = States.lower_children(element, source, NO_SLOTS)
        node = Document::Log.new(location: element.location, label: Reading.value(element, "label"),
                                 expr: Reading.value(element, "expr"),
                                 attribute_locations: Reading.locations(element, %w[label expr]))
        [[:content_node, node], errors]
      end

      # An `<assign>`'s children are its in-line value and are never walked.
      def assign(element, source)
        path = Reading.value(element, "location")
        return [nil, [Errors.missing_attribute("assign", "location", element.location)]] if path.nil?

        markup, markup_location = DataModel.markup(element, source)
        node = Document::Assign.new(
          location: path, node_location: element.location, expr: Reading.value(element, "expr"),
          text: Reading.text(element), markup:, markup_location:,
          attribute_locations: Reading.locations(element, %w[location expr])
        )
        [[:content_node, node], Reading::EMPTY]
      end

      # A `<send>`: its attributes, its `<param>` children and its last
      # `<content>`.
      def send_node(element, source)
        filled, errors = States.lower_children(element, source, SEND_SLOTS)
        fields = SEND_ATTRIBUTES.to_h { |name| [name.to_sym, Reading.value(element, name)] }
        node = Document::Send.new(
          location: element.location, **fields, namelist: Reading.list(element, "namelist"),
          params: Placement.many(filled, :params), content: filled[:content],
          attribute_locations: Reading.locations(element, [*SEND_ATTRIBUTES, "namelist"])
        )
        [[:content_node, node], errors]
      end

      # A `<cancel>`: its `sendid` and `sendidexpr`; it takes no children.
      def cancel(element, source)
        _filled, errors = States.lower_children(element, source, NO_SLOTS)
        node = Document::Cancel.new(location: element.location, sendid: Reading.value(element, "sendid"),
                                    sendidexpr: Reading.value(element, "sendidexpr"),
                                    attribute_locations: Reading.locations(element, %w[sendid sendidexpr]))
        [[:content_node, node], errors]
      end

      # A `<script>`'s text is its program. A `src` names a program to fetch,
      # and nothing is fetched, so a `<script src>` does not lower.
      def script(element, _source)
        errors = misplaced_children(element, "script")
        if Reading.attribute(element, "src")
          return [nil, errors + [Errors.unsupported_attribute("script", "src", element.location)]]
        end

        node = Document::Script.new(location: element.location, text: Reading.text(element), src: nil,
                                    attribute_locations: Reading::NO_LOCATIONS)
        [[:content_node, node], errors]
      end

      # Lowers an element whose node needs the attribute `name`: walks its
      # children, then answers nil and the missing-attribute error when it is
      # absent, or the node the block makes from its value and the filled
      # fields (the block answers it tagged), with the misplaced children.
      def required(element, source, slots, name)
        results, errors = Lowering.walk_children(element, source)
        value = Reading.value(element, name)
        return [nil, errors + [Errors.missing_attribute(local(element), name, element.location)]] if value.nil?

        filled, misplaced = Placement.fold(results, slots, element.name)
        [yield(value, filled), errors + misplaced]
      end

      # Each element child of an element that holds only text, misplaced.
      def misplaced_children(element, parent)
        element.children.grep(XML::Element).map { |child| Errors.misplaced(child.name, parent, child.location) }
      end

      # The local name of `element`, its prefix dropped.
      def local(element) = element.name.split(":", 2).last
    end
  end
end

require_relative "branches"
