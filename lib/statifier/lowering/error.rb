# frozen_string_literal: true

module Statifier
  module Lowering
    # Why a tree did not lower: a reason symbol, the detail that reason
    # carries (a frozen Hash), a message for a person, and the span of the
    # element, attribute or text refused. The reasons and their details:
    #
    # - `:unsupported_element` (`name`): an element in SCXML's vocabulary
    #   that no builder reads, `<scxml>` below the root included;
    # - `:misplaced_element` (`name`, `parent`): an element its parent has
    #   no place for;
    # - `:stray_text` (`text`, trimmed): text that is not blank where the
    #   content model has no room for it;
    # - `:unexpected_root` (`name`): a root that is not `<scxml>`;
    # - `:missing_attribute` (`element`, `attribute`): a required attribute
    #   absent, so the element's node cannot be made;
    # - `:foreign_element` (`name`, `uri`): an element in another namespace;
    # - `:unexpected_attribute` (`element`, `attribute`): an attribute on
    #   `<else>`, which takes none;
    # - `:unsupported_attribute` (`element`, `attribute`): `<script src>`,
    #   which the specification defines and this engine does not fetch.
    #
    # @api private
    Error = ::Data.define(:reason, :detail, :message, :location)

    # The constructors of {Error}, one per reason, with the reference's
    # messages.
    #
    # @api private
    module Errors
      # The edge characters a trim removes: Unicode white space.
      TRIM = "\\t\\n\\v\\f\\r \\u0085\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000"
      TRIM_EDGES = /\A[#{TRIM}]+|[#{TRIM}]+\z/
      PREVIEW = 40
      ESCAPES = { "\\" => "\\\\", '"' => "\\\"", "\n" => "\\n", "\t" => "\\t", "\r" => "\\r", "\#{" => "\\\#{" }.freeze

      module_function

      # @return [Error] `:unsupported_element`
      def unsupported(name, location)
        make(:unsupported_element, { name: }, "unsupported element #{quote(name)}", location)
      end

      # @return [Error] `:misplaced_element`
      def misplaced(name, parent, location)
        make(:misplaced_element, { name:, parent: },
             "element #{quote(name)} is not allowed inside #{quote(parent)}", location)
      end

      # @return [Error] `:stray_text`, the message quoting at most the first
      #   40 characters of the trimmed text
      def stray_text(text, location)
        trimmed = trim(text)
        clusters = trimmed.grapheme_clusters
        preview = clusters.size > PREVIEW ? "#{clusters.first(PREVIEW).join}..." : trimmed
        make(:stray_text, { text: trimmed }, "stray text #{quote(preview)} is not allowed here", location)
      end

      # @return [Error] `:unexpected_root`
      def unexpected_root(name, location)
        make(:unexpected_root, { name: }, "expected the document root to be <scxml>, got #{quote(name)}", location)
      end

      # @return [Error] `:missing_attribute`
      def missing_attribute(element, attribute, location)
        make(:missing_attribute, { element:, attribute: },
             "element #{quote(element)} is missing required attribute #{quote(attribute)}", location)
      end

      # @return [Error] `:foreign_element`
      def foreign_element(name, uri, location)
        make(:foreign_element, { name:, uri: },
             "element #{quote(name)} is bound to foreign namespace #{quote(uri)}, not SCXML", location)
      end

      # @return [Error] `:unexpected_attribute`
      def unexpected_attribute(element, attribute, location)
        make(:unexpected_attribute, { element:, attribute: },
             "element #{quote(element)} does not accept attribute #{quote(attribute)}", location)
      end

      # @return [Error] `:unsupported_attribute`
      def unsupported_attribute(element, attribute, location)
        make(:unsupported_attribute, { element:, attribute: },
             "element #{quote(element)}'s #{quote(attribute)} attribute is defined by the spec " \
             "but not implemented by this engine", location)
      end

      # `text` with Unicode white space trimmed from both ends.
      def trim(text) = text.gsub(TRIM_EDGES, "").freeze

      # `text` in double quotes, escaped as the reference quotes it.
      def quote(text) = %("#{text.gsub(/\\|"|\n|\t|\r|\#\{/, ESCAPES)}").freeze

      # An {Error} with its detail and message frozen.
      def make(reason, detail, message, location)
        Error.new(reason:, detail: detail.transform_values(&:freeze).freeze, message: message.freeze, location:)
      end
    end
  end
end
