# frozen_string_literal: true

module Statifier
  module XML
    # The namespace declarations in scope at an element: the default
    # namespace (nil when none is declared) and the bound prefixes. Each
    # element folds its own `xmlns` and `xmlns:prefix` attributes over the
    # scope it inherits, so a declaration reaches its element's subtree and
    # no further. A value binds as written, the empty string included: an
    # empty declaration (`xmlns=""`, `xmlns:p=""`) binds the empty URI and
    # undeclares nothing, as the reference's namespace scope does.
    #
    # @api private
    Scope = Data.define(:default, :prefixes) do
      # @param attributes [Array<Attribute>] an element's own attributes
      # @return [Scope] the scope for that element's subtree
      def declare(attributes)
        declared = attributes.select { |attribute| attribute.name.start_with?("xmlns") }
        return self if declared.empty?

        declared.reduce(self) { |scope, attribute| scope.bind(attribute.name, attribute.value) }
      end

      # @param name [String] an attribute name, perhaps a declaration
      # @param uri [String] its value
      # @return [Scope] this scope with the declaration folded in, if it is one
      def bind(name, uri)
        return with(default: uri) if name == "xmlns"
        return self unless name.start_with?("xmlns:") && name.length > 6

        with(prefixes: prefixes.merge(name.delete_prefix("xmlns:") => uri).freeze)
      end

      # @param name [String] a qualified element name, prefix included
      # @return [String, nil] the namespace it resolves to, or nil when no
      #   declaration is in scope for it
      def resolve(name)
        prefix, local = name.split(":", 2)
        local.nil? ? default : prefixes[prefix]
      end
    end

    # The scope outside the root element: nothing declared.
    Scope::EMPTY = Scope.new(default: nil, prefixes: {}.freeze)
  end
end
