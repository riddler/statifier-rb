# frozen_string_literal: true

module Statifier
  module XML
    # Reading start tags, end tags and attributes.
    #
    # @api private
    module Tags
      # XML 1.0's NameStartChar and NameChar productions.
      NAME_START = "A-Za-z_:\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u02FF\\u0370-\\u037D\\u037F-\\u1FFF" \
                   "\\u200C\\u200D\\u2070-\\u218F\\u2C00-\\u2FEF\\u3001-\\uD7FF\\uF900-\\uFDCF\\uFDF0-\\uFFFD" \
                   "\\u{10000}-\\u{EFFFF}"
      NAME = /[#{NAME_START}][#{NAME_START}\-.0-9\u00B7\u0300-\u036F\u203F\u2040]*/
      START_TAG = /<[#{NAME_START}]/
      TAG_END = %r{/?>}

      # An element whose end tag is still to come.
      OpenElement = Struct.new(:name, :namespace, :attributes, :children, :start, :scope) do
        # @param location [Location] the element's whole span
        # @return [Element] the element, its children frozen
        def finish(location) = Element.new(name:, namespace:, attributes:, children: children.freeze, location:)
      end

      private

      # Reads a name at the read position.
      def read_name
        name = @cursor.scan(NAME)
        return name.freeze if name

        refuse_unexpected_end if @cursor.eos?
        @cursor.refuse(:expected_name, "expected a name")
      end

      # Reads a start tag, `<name (S attribute)* S? (> | />)`, under the
      # namespace scope it inherits. Answers the open element and whether
      # the tag closed itself.
      def read_start_tag(inherited)
        start = @cursor.mark
        @cursor.skip("<")
        name = read_name
        attributes = read_attributes
        closed = !@cursor.skip("/>").nil?
        @cursor.skip(">") unless closed
        scope = inherited.declare(attributes)
        [OpenElement.new(name, scope.resolve(name), attributes, [], start, scope), closed]
      end

      def read_attributes
        attributes = []
        loop do
          spaced = @cursor.skip_whitespace
          return attributes.freeze if @cursor.at?(TAG_END)

          refuse_unexpected_end if @cursor.eos?
          @cursor.refuse(:expected_whitespace, "expected whitespace before an attribute") unless spaced
          attributes << read_attribute
        end
      end

      # Reads `name S? = S? quoted-value`.
      def read_attribute
        start = @cursor.mark
        name = read_name
        expect_equals(name)
        quote = expect_quote(name)
        value_start = @cursor.mark
        value = read_value(quote)
        value_location = @cursor.span(value_start)
        @cursor.skip(quote)
        Attribute.new(name:, value:, location: @cursor.span(start), value_location:)
      end

      def expect_equals(name)
        @cursor.skip_whitespace
        unless @cursor.skip("=")
          refuse_unexpected_end if @cursor.eos?
          @cursor.refuse(:expected_equals, "expected '=' after attribute #{name}")
        end
        @cursor.skip_whitespace
      end

      def expect_quote(name)
        quote = @cursor.scan(/["']/)
        return quote if quote

        refuse_unexpected_end if @cursor.eos?
        @cursor.refuse(:expected_quote, "expected a quoted value for attribute #{name}")
      end

      # Reads `</name S? >` and closes `open` with it.
      def read_end_tag(open)
        start = @cursor.mark
        @cursor.skip("</")
        name = read_name
        @cursor.skip_whitespace
        expect_tag_end
        return open.finish(@cursor.span(open.start)) if name == open.name

        @cursor.refuse(:mismatched_end_tag, "end tag </#{name}> where </#{open.name}> was due", start)
      end

      def expect_tag_end
        return if @cursor.skip(">")

        refuse_unexpected_end if @cursor.eos?
        @cursor.refuse(:expected_tag_end, "expected '>' to end the tag")
      end
    end
  end
end
