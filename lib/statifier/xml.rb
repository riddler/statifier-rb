# frozen_string_literal: true

require "strscan"

require_relative "xml/nodes"
require_relative "xml/cursor"
require_relative "xml/scope"
require_relative "xml/character_data"
require_relative "xml/markup"
require_relative "xml/tags"
require_relative "xml/parser"

module Statifier
  # XML source in, a generic element tree out: the first step of reading a
  # chart. This layer knows XML and nothing else; a later one gives the names
  # meaning. It is a small hand-written reader of the XML that SCXML
  # documents use, and needs no XML library.
  #
  # Beyond splitting the markup, it normalizes attribute values (XML 1.0
  # section 3.3.3), folds line breaks in character data (section 2.11),
  # expands the five predefined entities and character references, and gives
  # every element the namespace its name resolves to under the declarations
  # in scope. It validates no name against any vocabulary, keeps duplicate
  # attributes and whitespace-only text, and reads no document type
  # definition. Comments, processing instructions, the XML declaration and a
  # document type declaration produce no nodes, and anything outside the
  # root element is discarded.
  #
  # @api private
  module XML
    # The encodings whose strings are read from their bytes as UTF-8.
    READ_AS_BYTES = [Encoding::BINARY, Encoding::US_ASCII].freeze
    private_constant :READ_AS_BYTES

    # Parses `source` into its root element, or answers why it cannot.
    # Malformed input is never raised: the result carries the refusal, with
    # a message and the line and column where reading stopped.
    #
    # The document is read as UTF-8. A string tagged binary or US-ASCII is
    # read from its bytes; a string in any other encoding is transcoded
    # first, and the byte offsets in every {Location} are then offsets into
    # the transcoded text. A leading byte order mark is refused, as the
    # reference refuses it.
    #
    # @param source [String] the document
    # @return [Result] the root {Element} as `value`, or a {ParseError} as
    #   `error`
    # @raise [TypeError] when `source` is not a String
    def self.parse(source)
      raise TypeError, "expected a String, got #{source.class}" unless source.is_a?(String)

      Result.new(value: Parser.new(utf8(source)).parse, error: nil)
    rescue Refused => e
      Result.new(value: nil, error: e.error)
    end

    # @api private
    def self.utf8(source)
      text = transcode(source)
      unless text.valid_encoding?
        Cursor.new(text).tap { _1.move_to(first_invalid_byte(text)) }
              .refuse(:invalid_encoding, "the document is not valid UTF-8")
      end
      Cursor.new(text).refuse(:byte_order_mark, "a byte order mark is not read") if text.start_with?("\uFEFF")
      text
    end

    # @api private
    def self.transcode(source)
      return source if source.encoding == Encoding::UTF_8
      return source.dup.force_encoding(Encoding::UTF_8) if READ_AS_BYTES.include?(source.encoding)

      source.encode(Encoding::UTF_8)
    rescue EncodingError
      Cursor.new("").refuse(:invalid_encoding, "the document cannot be read as UTF-8")
    end

    # @api private
    def self.first_invalid_byte(text)
      text.each_char.take_while(&:valid_encoding?).sum(&:bytesize)
    end

    private_class_method :utf8, :transcode, :first_invalid_byte
  end
end
