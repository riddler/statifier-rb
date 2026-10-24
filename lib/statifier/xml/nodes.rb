# frozen_string_literal: true

module Statifier
  module XML
    # A source span: 1-based lines and columns, 0-based byte offsets into the
    # document read as UTF-8, and an exclusive end. Columns count code
    # points, and only a line feed starts a new line. An element's span runs
    # from the `<` of its start tag to the byte after the `>` of its end tag
    # (the tag itself when it closes itself), so its start line and column
    # are those of its `<`.
    Location = Data.define(:start_line, :start_column, :start_offset, :end_line, :end_column, :end_offset) do
      # The raw text this span covers.
      #
      # @param source [String] the UTF-8 document the span was read from
      # @return [String] the bytes from the start offset up to the end offset
      def slice(source) = source.byteslice(start_offset, end_offset - start_offset)
    end

    # One attribute, in document order. `value` is normalized (XML 1.0
    # section 3.3.3) and its references expanded; `location` covers
    # `name="value"` with its quotes, and `value_location` only the raw text
    # inside the quotes.
    Attribute = Data.define(:name, :value, :location, :value_location)

    # An element. `name` is the qualified name as written, prefix included;
    # `namespace` is the URI that name resolves to under the declarations in
    # scope (the empty string when an empty declaration is in scope for it),
    # or nil when none is. `attributes` keeps document order and every
    # duplicate; `children` interleaves elements and text runs.
    Element = Data.define(:name, :namespace, :attributes, :children, :location)

    # A run of character data between two tags, coalesced across any
    # comment, processing instruction or CDATA section inside it. `value` is
    # expanded and line-break folded (XML 1.0 section 2.11); `location`
    # covers the raw run.
    Text = Data.define(:value, :location)

    # Why a document was refused: a reason symbol, a message for a person
    # that ends with the line and column, and the zero-width location where
    # reading stopped.
    ParseError = Data.define(:reason, :message, :location)

    # What {XML.parse} answers: the root element as `value`, or the refusal
    # as `error`.
    Result = Data.define(:value, :error) do
      # @return [Boolean] true when the document was read
      def ok? = error.nil?
    end
  end
end
