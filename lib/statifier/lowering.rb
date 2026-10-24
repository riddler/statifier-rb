# frozen_string_literal: true

require_relative "document"
require_relative "lowering/error"
require_relative "lowering/reading"
require_relative "lowering/placement"
require_relative "lowering/states"
require_relative "lowering/executable"
require_relative "lowering/data"

module Statifier
  # The reader's element tree in, the typed chart ({Document}) out: the
  # second step of reading a chart, a port of the reference's lowering.
  #
  # One walk. Each element is lowered by the builder its local name selects;
  # a builder lowers its children first, then places each into a field of
  # its own node, and a child its node has no place for is misplaced. An
  # element is SCXML's own when its name resolves to the SCXML namespace or
  # to none, so a chart that declares no namespace lowers as its declared
  # twin does; reporting a missing declaration is a later check's.
  # `<content>`, `<assign>`, `<data>` and `<script>` hold text as their
  # payload and are exempt from the stray-text rule; the element children of
  # `<content>` and `<assign>` are kept as a slice of the source, never
  # lowered.
  #
  # The walk does not stop at the first refusal: it collects every one, and
  # the chart is answered only when there are none, never a partial one.
  #
  # @api private
  module Lowering
    # The SCXML namespace.
    SCXML_NAMESPACE = "http://www.w3.org/2005/07/scxml"

    # The builder of each element that may appear below the root. `<scxml>`
    # is not one: it is only ever the root.
    BUILDERS = {
      "state" => [States, :state], "parallel" => [States, :parallel], "final" => [States, :final],
      "history" => [States, :history], "initial" => [States, :initial], "transition" => [States, :transition],
      "onentry" => [States, :onentry], "onexit" => [States, :onexit], "finalize" => [States, :finalize],
      "raise" => [Executable, :raise_node], "log" => [Executable, :log], "assign" => [Executable, :assign],
      "if" => [Executable, :if_node], "elseif" => [Executable, :elseif], "else" => [Executable, :else_node],
      "foreach" => [Executable, :foreach], "script" => [Executable, :script], "send" => [Executable, :send_node],
      "cancel" => [Executable, :cancel], "datamodel" => [DataModel, :datamodel], "data" => [DataModel, :data],
      "donedata" => [DataModel, :donedata], "param" => [DataModel, :param], "content" => [DataModel, :content],
      "invoke" => [DataModel, :invoke]
    }.freeze

    # The encodings whose strings the reader reads from their bytes.
    READ_AS_BYTES = [Encoding::BINARY, Encoding::US_ASCII].freeze

    # What {Lowering.lower} answers: the chart as `value`, or every refusal,
    # in document order, as `errors`.
    Result = ::Data.define(:value, :errors) do
      # @return [Boolean] true when the tree lowered
      def ok? = errors.empty?
    end

    # Lowers a parsed `<scxml>` element tree into its typed chart.
    #
    # @param root [XML::Element] the root element {XML.parse} answered
    # @param source [String] the document it was parsed from; `<content>` and
    #   `<assign>` slice their markup out of it
    # @return [Result] the {Document} as `value`, or the {Error}s as `errors`
    def self.lower(root, source)
      refusal = root_refusal(root)
      return refuse([refusal]) if refusal

      document, errors = States.scxml(root, utf8(source))
      errors.empty? ? Result.new(value: document, errors: Reading::EMPTY) : refuse(errors)
    end

    # Why a root does not lower: it is foreign, or it is not `<scxml>`.
    def self.root_refusal(root)
      return Errors.foreign_element(root.name, root.namespace, root.location) unless scxml?(root.namespace)

      name = local_name(root.name)
      Errors.unexpected_root(name, root.location) unless name == "scxml"
    end

    # Lowers an element's children: each child element by its builder, each
    # text run checked against the stray-text rule. Answers the tagged
    # results in document order (nil for an element that made no node) and
    # the errors newest first, as the reference accumulates them.
    def self.walk_children(element, source)
      element.children.each_with_object([[], []]) do |child, (results, errors)|
        result, child_errors = child.is_a?(XML::Text) ? [nil, walk_text(child)] : walk_element(child, source)
        results << result
        errors.unshift(*child_errors.reverse)
      end
    end

    def self.walk_text(text)
      Reading.blank?(text.value) ? Reading::EMPTY : [Errors.stray_text(text.value, text.location)]
    end

    # A child element lowered by its builder, or refused when it is foreign
    # or no builder reads it.
    def self.walk_element(element, source)
      return [nil, [Errors.foreign_element(element.name, element.namespace, element.location)]] \
        unless scxml?(element.namespace)

      builder, method = BUILDERS[local_name(element.name)]
      return [nil, [Errors.unsupported(element.name, element.location)]] if builder.nil?

      builder.public_send(method, element, source)
    end

    def self.scxml?(uri) = uri.nil? || uri == SCXML_NAMESPACE

    def self.local_name(name) = name.split(":", 2).last

    # Every error in document order: by start offset, found order kept at
    # one offset.
    def self.refuse(errors)
      sorted = errors.each_with_index.sort_by { |error, index| [error.location.start_offset, index] }.map(&:first)
      Result.new(value: nil, errors: sorted.freeze)
    end

    # The source as the reader read it, so that its byte offsets slice it.
    def self.utf8(source)
      return source if source.encoding == Encoding::UTF_8
      return source.dup.force_encoding(Encoding::UTF_8) if READ_AS_BYTES.include?(source.encoding)

      source.encode(Encoding::UTF_8)
    end

    private_class_method :root_refusal, :walk_text, :walk_element, :scxml?, :local_name, :refuse, :utf8
  end
end
