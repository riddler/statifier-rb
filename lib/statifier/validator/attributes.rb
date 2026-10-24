# frozen_string_literal: true

module Statifier
  module Validator
    # The check of the markup itself: an attribute name appears once on a
    # tag (XML 1.0 section 3.1, "Unique Att Spec"). The reader keeps every
    # repeated attribute and lowering keeps the first, so the repeat is read
    # back out of the source: every start tag, markup inside `<content>`,
    # `<assign>` and `<data>` included.
    #
    # @api private
    module Attributes
      module_function

      # Each later occurrence of a name on one tag, at its own span; names
      # are compared as written, prefix included.
      def duplicates(_document, context)
        parsed = XML.parse(context.source)
        parsed.ok? ? element_duplicates(parsed.value) : []
      end

      # The repeats on `element` and on every element below it, in document
      # order.
      def element_duplicates(element)
        seen = {}
        own = element.attributes.filter_map do |attribute|
          next seen[attribute.name] = nil unless seen.key?(attribute.name)

          Findings.error(:duplicate_attribute, attribute.location, element: element.name, attribute: attribute.name)
        end
        own + element.children.grep(XML::Element).flat_map { element_duplicates(_1) }
      end
    end
  end
end
