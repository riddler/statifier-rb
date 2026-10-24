# frozen_string_literal: true

module Statifier
  module XML
    # The constructs that produce no node: comments, processing
    # instructions, the XML declaration and the document type declaration.
    #
    # @api private
    module Markup
      S = "[\\x20\\t\\r\\n]"
      EQ = "#{S}*=#{S}*".freeze

      # What follows `<?xml` in an XML declaration (XML 1.0 production 23).
      # Group 1 or 2 is the declared encoding.
      DECLARATION = /
        #{S}+version#{EQ}(?:"1\.[0-9]+"|'1\.[0-9]+')
        (?:#{S}+encoding#{EQ}(?:"([A-Za-z][A-Za-z0-9._-]*)"|'([A-Za-z][A-Za-z0-9._-]*)'))?
        (?:#{S}+standalone#{EQ}(?:"(?:yes|no)"|'(?:yes|no)'))?
        #{S}*\?>
      /x

      private

      # Skips whitespace, comments and processing instructions outside the
      # root element; before it (`prolog`) also one document type
      # declaration. Stops at the first other character.
      def skip_misc(prolog:)
        doctype = prolog
        loop do
          @cursor.skip_whitespace
          next skip_comment if @cursor.at?("<!--")
          next skip_processing_instruction if @cursor.at?("<?")
          return unless doctype && @cursor.at?("<!DOCTYPE")

          skip_doctype
          doctype = false
        end
      end

      # Skips `<!-- ... -->`, refusing `--` inside it as XML 1.0 section 2.5
      # does.
      def skip_comment
        @cursor.skip("<!--")
        @cursor.refuse_at_end(:unterminated_comment, "a comment is never closed") unless @cursor.skip_until(/--/)
        return if @cursor.skip(">")

        @cursor.move_to(@cursor.offset - 2)
        @cursor.refuse(:double_hyphen_in_comment, "'--' is not allowed inside a comment")
      end

      # Skips `<? ... ?>`. The target `xml` is the XML declaration, read only
      # at the very start of the document; any other spelling of it is
      # reserved.
      def skip_processing_instruction
        start = @cursor.mark
        @cursor.skip("<?")
        target = read_name
        return read_declaration(start) if target == "xml" && start.offset.zero?

        refuse_reserved(target, start) if target.casecmp?("xml")
        return if @cursor.skip_until(/\?>/)

        @cursor.refuse_at_end(:unterminated_processing_instruction, "a processing instruction is never closed")
      end

      def read_declaration(start)
        @cursor.refuse(:malformed_xml_declaration, "the XML declaration is malformed", start) \
          unless @cursor.skip(DECLARATION)
        encoding = @cursor[1] || @cursor[2]
        return if encoding.nil? || encoding.casecmp?("UTF-8")

        @cursor.refuse(:unsupported_encoding, "the document declares the encoding #{encoding}; only UTF-8 is read",
                       start)
      end

      def refuse_reserved(target, start)
        if target == "xml"
          @cursor.refuse(:misplaced_xml_declaration,
                         "the XML declaration is allowed only at the start of the document", start)
        end
        @cursor.refuse(:reserved_target, "the processing instruction target #{target} is reserved", start)
      end

      # Skips `<!DOCTYPE ... >` as the reference reads one: the declaration
      # ends at the `>` that brings the count of open angle brackets,
      # `<!DOCTYPE` included, to zero. The reference also finds the end a
      # second way, at the first `>` outside square brackets, and reads the
      # document only when the two ends agree or nothing between them is
      # markup. Neither reading treats a quote specially, and the
      # declarations inside are not read: only the predefined entities
      # expand.
      def skip_doctype
        start = @cursor.mark
        @cursor.skip("<!DOCTYPE")
        angle, bracket = DoctypeEnds.new(@cursor.text, @cursor.offset).ends
        unless angle && bracket
          @cursor.refuse_at_end(:unterminated_doctype, "a document type declaration is never closed")
        end
        low, high = [angle, bracket].minmax
        refuse_ambiguous_doctype(start) if @cursor.text.byteslice(low, high - low).include?("<")
        @cursor.move_to(angle)
      end

      def refuse_ambiguous_doctype(start)
        @cursor.refuse(:ambiguous_doctype,
                       "the document type declaration has two different ends with markup between them", start)
      end
    end

    # The two ends of a document type declaration, read from just after
    # `<!DOCTYPE`: the byte offset after the `>` that balances the angle
    # brackets, and after the first `>` outside square brackets (a `]`
    # never taking the depth below zero). Either is nil when the document
    # ends first.
    #
    # @api private
    class DoctypeEnds
      # @param text [String] the document
      # @param offset [Integer] the byte offset just after `<!DOCTYPE`
      def initialize(text, offset)
        @scanner = StringScanner.new(text)
        @scanner.pos = offset
        @angles = 1
        @depth = 0
      end

      # @return [Array(Integer, Integer)] the angle-bracket end and the
      #   square-bracket end, each nil when the document ends first
      def ends
        step(@scanner.matched) while (@angle.nil? || @bracket.nil?) && @scanner.skip_until(/[<>\[\]]/)
        [@angle, @bracket]
      end

      private

      def step(char)
        case char
        when "<" then @angles += 1
        when "[" then @depth += 1
        when "]" then @depth = [@depth - 1, 0].max
        else close
        end
      end

      def close
        @bracket ||= @scanner.pos if @depth.zero?
        @angle ||= @scanner.pos if @angles == 1
        @angles -= 1
      end
    end
  end
end
