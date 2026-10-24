# frozen_string_literal: true

module Statifier
  module XML
    # Reading the text of a document: character data, CDATA sections,
    # attribute values and the references inside them.
    #
    # Character data folds line breaks per XML 1.0 section 2.11: a literal
    # CR LF pair and a literal lone CR each become one LF, inside a CDATA
    # section too, while a CR decoded from `&#xD;` stays a CR. An attribute
    # value is normalized per section 3.3.3: a literal TAB, LF or CR becomes a
    # space, a literal CR LF pair becomes one space, a character reference
    # keeps its decoded character, and nothing is trimmed or collapsed. Both
    # read the raw source, so a CR followed by a comment is a lone CR.
    #
    # The five predefined entities and decimal and hex character references
    # expand in text and in attribute values; any other reference is refused.
    #
    # @api private
    module CharacterData
      PREDEFINED = { "amp" => "&", "lt" => "<", "gt" => ">", "quot" => '"', "apos" => "'" }.freeze

      # A reference body runs to the first `;` and never spans whitespace,
      # markup or a quote; one that does means the `&` began no reference.
      REFERENCE = /&([^;\x20\t\r\n<&"']+);/
      HEX = /\A#x([0-9A-Fa-f]+)\z/
      DECIMAL = /\A#([0-9]+)\z/

      # The characters XML 1.0's Char production leaves out that a valid
      # UTF-8 string can still hold (a surrogate cannot be valid UTF-8).
      EXCLUDED = "\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\uFFFE\\uFFFF"
      INVALID = /[#{EXCLUDED}]/
      TEXT_RUN = /[^<&\r\]#{EXCLUDED}]+/
      CDATA_RUN = /[^\]\r#{EXCLUDED}]+/
      VALUE_RUNS = {
        '"' => /[^"<&\t\n\r#{EXCLUDED}]+/,
        "'" => /[^'<&\t\n\r#{EXCLUDED}]+/
      }.freeze

      private

      # Reads character data up to the next `<` or the end into `buffer`.
      def read_character_data(buffer)
        buffer << (@cursor.scan(TEXT_RUN) || text_special) until @cursor.eos? || @cursor.at?("<")
      end

      def text_special
        return read_reference if @cursor.at?("&")
        return line_break("\n") if @cursor.at?("\r")

        @cursor.refuse(:cdata_end_in_text, "']]>' is not allowed in character data") if @cursor.at?("]]>")
        return @cursor.getch if @cursor.at?("]")

        refuse_character
      end

      # Reads `<![CDATA[ ... ]]>` into `buffer`: the content verbatim except
      # that line breaks fold.
      def read_cdata(buffer)
        @cursor.skip("<![CDATA[")
        buffer << (@cursor.scan(CDATA_RUN) || cdata_special) until @cursor.skip("]]>")
      end

      def cdata_special
        @cursor.refuse_at_end(:unterminated_cdata, "a CDATA section is never closed") if @cursor.eos?
        return line_break("\n") if @cursor.at?("\r")
        return @cursor.getch if @cursor.at?("]")

        refuse_character
      end

      # Reads an attribute value up to its closing `quote`, which it leaves
      # unread, and answers it normalized.
      def read_value(quote)
        value = +""
        value << (@cursor.scan(VALUE_RUNS.fetch(quote)) || value_special) until @cursor.at?(quote)
        value.freeze
      end

      def value_special
        refuse_unexpected_end if @cursor.eos?
        @cursor.refuse(:lt_in_attribute_value, "'<' is not allowed in an attribute value") if @cursor.at?("<")
        return read_reference if @cursor.at?("&")
        return line_break(" ") if @cursor.at?("\r")
        return @cursor.getch && " " if @cursor.at?(/[\t\n]/)

        refuse_character
      end

      # Consumes a CR and the LF after it, if any, and answers `replacement`.
      def line_break(replacement)
        @cursor.skip(/\r\n?/)
        replacement
      end

      # Reads `&name;`, `&#digits;` or `&#xhex;` and answers the character it
      # stands for.
      def read_reference
        at = @cursor.mark
        @cursor.refuse(:malformed_reference, "'&' does not start a reference", at) unless @cursor.skip(REFERENCE)
        body = @cursor[1]
        return character_reference(body, at) if body.start_with?("#")

        PREDEFINED.fetch(body) { @cursor.refuse(:unknown_entity, "&#{body}; is not a predefined entity", at) }
      end

      def character_reference(body, at)
        digits = body[HEX, 1]
        code = digits ? digits.to_i(16) : body[DECIMAL, 1]&.to_i
        return code.chr(Encoding::UTF_8) if code && xml_char?(code)

        @cursor.refuse(:invalid_character_reference, "&#{body}; is not a valid character reference", at)
      end

      # XML 1.0's Char production.
      def xml_char?(code)
        [0x9, 0xA, 0xD].include?(code) || (0x20..0xD7FF).cover?(code) ||
          (0xE000..0xFFFD).cover?(code) || (0x10000..0x10FFFF).cover?(code)
      end

      def refuse_character
        code = @cursor.scan(INVALID).ord
        @cursor.move_to(@cursor.offset - code.chr(Encoding::UTF_8).bytesize)
        @cursor.refuse(:invalid_character, format("the character U+%04X is not allowed in XML", code))
      end

      def refuse_unexpected_end
        @cursor.refuse(:unexpected_end, "the document ends inside a tag")
      end
    end
  end
end
