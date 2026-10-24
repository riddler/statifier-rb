# frozen_string_literal: true

module Statifier
  module Lowering
    # Reading an element's attributes and text as the builders need them.
    #
    # @api private
    module Reading
      # What a list attribute splits on: Unicode white space except the
      # no-break spaces, as the reference splits it.
      SPLIT = /[\t\n\v\f\r \u0085\u1680\u2000-\u2006\u2008-\u200a\u2028\u2029\u205f\u3000]+/
      BLANK = /\A[#{Errors::TRIM}]*\z/
      EMPTY = [].freeze
      NO_LOCATIONS = {}.freeze

      module_function

      # The value of the first attribute written with `name`, or nil.
      def value(element, name) = attribute(element, name)&.value

      # An attribute split on white space: absent and empty both answer an
      # empty list, told apart by the attribute's location.
      def list(element, name)
        raw = value(element, name)
        raw.nil? ? EMPTY : raw.split(SPLIT).reject(&:empty?).map(&:freeze).freeze
      end

      # An attribute mapped through `mapping`, or `default` when it is absent
      # or not a key of `mapping`.
      def choice(element, name, mapping, default) = mapping.fetch(value(element, name), default)

      # The value spans of the named attributes that were written, keyed by
      # name as a Symbol.
      def locations(element, names)
        names.each_with_object({}) do |name, spans|
          found = attribute(element, name)
          spans[name.to_sym] = found.value_location if found&.value_location
        end.freeze
      end

      # The element's own character data, its text children joined.
      def text(element)
        element.children.grep(XML::Text).map(&:value).join.freeze
      end

      # Whether trimming Unicode white space from `text` leaves nothing.
      def blank?(text) = BLANK.match?(text)

      # The first attribute written with `name`, or nil.
      def attribute(element, name) = element.attributes.find { |candidate| candidate.name == name }
    end
  end
end
